-- Per-basic-block cycle estimates for the CH32V003 (QingKe V2A, rv32ec).
--
-- This is deliberately not the simulator debugger's per-instruction
-- cold-start estimate.  Flash code is fetch-limited at latency 1: the
-- simulator charges two cycles for every executed 4-byte chunk, and a taken
-- transfer ends the current fetch block.  The state that matters therefore
-- spans instructions, so this module reconstructs basic blocks and carries
-- the fetch phase across fallthrough edges.
--
-- The model is documented in the simulator at
-- ~/Projects/ch32v003-sim/doc/emulation-architecture.md ("Instruction
-- timing") and implemented in emulator/src/timing.c.

local M = {}

local function set(list)
  local result = {}
  for _, value in ipairs(list) do
    result[value] = true
  end
  return result
end

local CONDITIONAL = set({
  "beq",
  "bne",
  "blt",
  "bge",
  "bltu",
  "bgeu",
  "beqz",
  "bnez",
  "blez",
  "bgez",
  "bltz",
  "bgtz",
  "bgt",
  "ble",
  "bgtu",
  "bleu",
})

local UNCONDITIONAL = set({
  "j",
  "jal",
  "call",
  "tail",
})

local INDIRECT = set({
  "ret",
  "jr",
  "jalr",
  "mret",
  "sret",
  "uret",
  "ecall",
  "ebreak",
  "unimp",
})

local LOAD = set({
  "lb",
  "lh",
  "lw",
  "lbu",
  "lhu",
  "lwu",
  "ld",
  "flw",
  "fld",
  "lwsp",
  "ldsp",
  "flwsp",
  "fldsp",
})

local STORE = set({
  "sb",
  "sh",
  "sw",
  "sd",
  "fsw",
  "fsd",
  "swsp",
  "sdsp",
  "fswsp",
  "fsdsp",
})

local DIRECTIVE_SIZE = {
  [".word"] = 4,
  [".4byte"] = 4,
  [".long"] = 4,
  [".short"] = 2,
  [".half"] = 2,
  [".2byte"] = 2,
  [".byte"] = 1,
}

local function directive_size(mnemonic, operands)
  local size = DIRECTIVE_SIZE[mnemonic]
  if size then
    return size
  end
  if mnemonic == ".insn" then
    local n = operands:match("^%s*(%d+)")
    return n and tonumber(n) or nil
  end
  return nil
end

local function format_hex(value)
  return string.format("%x", value)
end

local function describe_target_sources(sources)
  if not sources or #sources == 0 then
    return "branch target"
  end
  if #sources == 1 then
    return "target of " .. sources[1].mnemonic .. " " .. format_hex(sources[1].addr)
  end
  return "target of " .. #sources .. " branches"
end

local function parse_target(operands)
  -- GNU objdump always prints a symbol target in angle brackets.  Keep a
  -- fallback for hand-written fixtures / other objdump variants.
  local hex = operands:match("([0-9a-fA-F]+)%s*<")
  if hex then
    return tonumber(hex, 16)
  end
  hex = operands:match("0x([0-9a-fA-F]+)")
  if hex then
    return tonumber(hex, 16)
  end
  hex = operands:match(",%s*([0-9a-fA-F]+)%s*$") or operands:match("^%s*([0-9a-fA-F]+)%s*$")
  if hex then
    return tonumber(hex, 16)
  end
  return nil
end

local function classify(insn)
  local mnemonic = insn.mnemonic:lower()
  local base = mnemonic:gsub("^c%.", "")

  if CONDITIONAL[mnemonic] or CONDITIONAL[base] then
    insn.kind = "cond"
    insn.target = parse_target(insn.operands)
  elseif UNCONDITIONAL[mnemonic] or UNCONDITIONAL[base] then
    insn.kind = "uncond"
    insn.target = parse_target(insn.operands)
    insn.call = mnemonic == "jal" or mnemonic == "call" or base == "jal" or base == "call"
  elseif INDIRECT[mnemonic] or INDIRECT[base] then
    insn.kind = "indirect"
  end

  if not insn.call and base == "jalr" then
    -- `jalr -24(ra)` / `jalr ra, ...` / `jalr t0` write the standard link
    -- register and are calls.  An explicit non-ra link register is not.
    local first = insn.operands:match("^%s*([%w%.]+)")
    insn.call = not first or first == "ra" or not insn.operands:find(",", 1, true)
  end

  insn.loadstore = LOAD[mnemonic] or LOAD[base] or STORE[mnemonic] or STORE[base] or false
end

local function parse_line(line, row)
  local addr_hex, rest = line:match("^%s*([0-9a-fA-F]+):%s*(.*)$")
  if not addr_hex then
    return nil
  end

  local size
  local text = rest
  local raw, stripped = rest:match("^([0-9a-fA-F]+)%s+(.*)$")
  if raw and (#raw == 4 or #raw == 8) then
    size = #raw / 2
    text = stripped
  end

  local mnemonic = text:match("^(%S+)")
  if not mnemonic or mnemonic == "..." then
    return nil
  end

  local operands = text:match("^%S+%s+(.*)$") or ""
  local is_data = mnemonic:sub(1, 1) == "."
  if is_data and not size then
    size = directive_size(mnemonic, operands)
  end

  local insn = {
    row = row,
    addr = tonumber(addr_hex, 16),
    size = size,
    mnemonic = mnemonic,
    operands = operands,
    text = text,
    is_data = is_data,
  }
  classify(insn)
  return insn
end

function M.parse_sizes(lines)
  local sizes = {}
  for _, line in ipairs(lines or {}) do
    local addr_hex, rest = line:match("^%s*([0-9a-fA-F]+):%s*(.*)$")
    if addr_hex then
      local raw = rest:match("^([0-9a-fA-F]+)%s+")
      if raw and (#raw == 4 or #raw == 8) then
        sizes[tonumber(addr_hex, 16)] = #raw / 2
      end
    end
  end
  return sizes
end

-- Sizes for the instruction rows in a display buffer.  The raw-byte pass
-- supplies nearly every size; the next-address distance covers displays
-- produced without raw bytes, and 4 bytes is the fallback for the last
-- instruction of a function.
function M.row_sizes(lines, sizes)
  sizes = sizes or {}
  local parsed = {}
  for row, line in ipairs(lines or {}) do
    local insn = parse_line(line, row)
    if insn then
      insn.size = insn.size or sizes[insn.addr]
      parsed[#parsed + 1] = insn
    end
  end

  local row_sizes = {}
  for i, insn in ipairs(parsed) do
    local size = insn.size
    if not size then
      local next_insn = parsed[i + 1]
      if next_insn then
        local diff = next_insn.addr - insn.addr
        if diff == 2 or diff == 4 then
          size = diff
        end
      end
    end
    if not size and not insn.is_data then
      size = 4
    end
    if size then
      row_sizes[insn.row] = size
    end
  end
  return row_sizes
end

-- Objdump's default alias mode prints both the 16-bit compressed NOP and the
-- 32-bit NOP as "nop".  Keep the rest of the display as objdump produced it,
-- but make the compressed form visible by relabelling the 2-byte row.
function M.relabel_compressed(lines, sizes)
  local row_sizes = M.row_sizes(lines, sizes)
  local result = {}
  for row, line in ipairs(lines or {}) do
    if row_sizes[row] == 2 then
      local insn = parse_line(line, row)
      if insn and insn.mnemonic == "nop" then
        local prefix, rest = line:match("^(%s*[0-9a-fA-F]+:%s*)(.*)$")
        if prefix then
          local replaced, count = rest:gsub("nop", "c.nop", 1)
          if count > 0 then
            line = prefix .. replaced
          end
        end
      end
    end
    result[#result + 1] = line
  end
  return result
end

local function simulate_block(block, entry, opts)
  local latency = tonumber(opts.latency) or 0
  local is_flash = opts.is_flash or function(addr)
    return addr < 0x4000
  end
  local data_is_flash = opts.data_is_flash and true or false

  local off = entry.off or (block.start_addr % 4)
  local pos = 0
  local carry = entry.carry or 0
  local active = is_flash(block.start_addr)
  local prev_end = entry.seq and block.start_addr or 0
  local cost = 0
  local last_chunks = 0
  local last_block_bytes = 0
  local last_addr = block.start_addr
  local last_size = 0
  local last_flash = active
  local line_costs = {}

  for _, insn in ipairs(block.instructions) do
    local flash = is_flash(insn.addr)

    if latency == 0 then
      local line_cost = 1
      if insn.loadstore then
        line_cost = line_cost + 1
      end
      local misaligned = flash
        and insn.size == 4
        and (insn.addr % 4) == 2
        and prev_end ~= insn.addr
      if misaligned then
        line_cost = line_cost + 1
      end
      cost = cost + line_cost

      local line = { total = line_cost, misaligned = misaligned }
      if insn.kind then
        line.total = nil
        line.taken = line_cost + 2
        if insn.kind == "cond" then
          line.fallthrough = line_cost
        end
      end
      line_costs[#line_costs + 1] = line

      prev_end = insn.addr + insn.size
      carry = carry + insn.size
      last_chunks = 0
      last_block_bytes = 0
    else
      local line_total
      if flash then
        if not active then
          off = insn.addr % 4
          pos = 0
          carry = 0
          active = true
        end
        local before = pos
        local after = pos + insn.size
        local chunks = math.floor((off + after) / 4) - math.floor((off + before) / 4)
        line_total = 2 * chunks
        cost = cost + line_total
        last_chunks = chunks
        last_block_bytes = carry
        carry = carry + insn.size
        pos = after
      else
        -- SRAM has no flash fetch phase.  Its data accesses still take one
        -- bus cycle at either latency.
        line_total = 1
        cost = cost + line_total
        last_chunks = 0
        last_block_bytes = 0
        carry = 0
        pos = 0
        active = false
      end

      if insn.loadstore then
        local extra
        if flash then
          local straddle = insn.size == 4 and (insn.addr % 4) == 2
          extra = ((straddle and last_block_bytes == 0) or last_chunks == 0) and 2 or 0
          if data_is_flash then
            extra = extra + 2
          end
        else
          extra = 1
          if data_is_flash then
            extra = extra + 2
          end
        end
        line_total = line_total + extra
        cost = cost + extra
      end

      line_costs[#line_costs + 1] = { total = line_total }
      prev_end = insn.addr + insn.size
    end

    last_addr = insn.addr
    last_size = insn.size
    last_flash = flash
  end

  local term = block.terminator
  local taken
  local fallthrough

  if term then
    local overhead
    if latency == 0 or not last_flash then
      overhead = 2
    elseif term.kind == "cond" and last_size == 4 and (last_addr % 4) == 0 then
      overhead = 2
    elseif last_block_bytes == 0 and ((last_addr + last_size) % 4) == 0 and last_chunks > 0 then
      overhead = 2
    else
      overhead = 4
    end
    taken = cost + overhead
    if term.kind == "cond" then
      fallthrough = cost
    end
    if latency == 1 then
      local last_line = line_costs[#line_costs]
      local base = last_line.total
      last_line.total = nil
      last_line.taken = base + overhead
      if term.kind == "cond" then
        last_line.fallthrough = base
      end
    end
  else
    fallthrough = cost
  end

  return {
    total = term and nil or cost,
    taken = taken,
    fallthrough = fallthrough,
    carry_out = carry,
    line_costs = line_costs,
  }
end

local function entry_key(entry)
  return string.format("%d:%d:%d", entry.off or 0, entry.carry or 0, entry.seq and 1 or 0)
end

local function taken_entry(term, target, is_flash)
  if not target then
    return nil
  end
  local off
  if is_flash(target)
    and math.floor(target / 4) == math.floor(term.addr / 4)
    and target > term.addr
  then
    off = 0
  else
    off = target % 4
  end
  return { off = off, carry = 0, seq = false }
end

local function minmax(values)
  local min
  local max
  for _, value in ipairs(values) do
    if not min or value < min then
      min = value
    end
    if not max or value > max then
      max = value
    end
  end
  return min, max
end

local function sorted_unique(values)
  table.sort(values)
  local result = {}
  local last
  for _, value in ipairs(values) do
    if value ~= last then
      result[#result + 1] = value
      last = value
    end
  end
  return result
end

-- These are discrete feasible totals, not a continuous interval.  A lone
-- `ret` at latency 1 can be 4 or 6 cycles depending on its entry state; 5
-- never occurs.  Prefer listing the actual values so a range such as "4–6"
-- does not falsely imply every number in between is possible.
local function range_text(min, max, values)
  if not min then
    return "?"
  end
  if values and #values > 1 then
    if #values == 2 then
      return tostring(values[1]) .. " or " .. tostring(values[2])
    end
    local parts = {}
    for _, value in ipairs(values) do
      parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, ", ")
  end
  if min == max then
    return tostring(min)
  end
  return tostring(min) .. "\226\128\147" .. tostring(max)
end

function M.format(annotation)
  if annotation.kind == "conditional" then
    return "taken "
      .. range_text(annotation.taken_min, annotation.taken_max, annotation.taken_values)
      .. " / fallthrough "
      .. range_text(
        annotation.fallthrough_min,
        annotation.fallthrough_max,
        annotation.fallthrough_values
      )
      .. " cyc"
  elseif annotation.kind == "taken" then
    return range_text(annotation.taken_min, annotation.taken_max, annotation.taken_values) .. " cyc"
  end
  return range_text(annotation.total_min, annotation.total_max, annotation.total_values) .. " cyc"
end

local function short_format(annotation)
  if not annotation then
    return "?"
  end
  if annotation.kind == "conditional" then
    local taken = range_text(annotation.taken_min, annotation.taken_max, annotation.taken_values)
    local fallthrough = range_text(
      annotation.fallthrough_min,
      annotation.fallthrough_max,
      annotation.fallthrough_values
    )
    if (annotation.taken_values and #annotation.taken_values > 1)
      or (annotation.fallthrough_values and #annotation.fallthrough_values > 1)
    then
      return "(" .. taken .. ")/(" .. fallthrough .. ")"
    end
    return taken .. "/" .. fallthrough
  elseif annotation.kind == "taken" then
    return range_text(annotation.taken_min, annotation.taken_max, annotation.taken_values)
  end
  return range_text(annotation.total_min, annotation.total_max, annotation.total_values)
end

function M.format_short(annotation)
  return short_format(annotation)
end

function M.format_compare(latency0, latency1)
  return "L0 "
    .. short_format(latency0)
    .. " \194\183 L1 "
    .. short_format(latency1)
    .. " cyc"
end

function M.format_line(annotation)
  return "L0 " .. short_format(annotation)
end

local function misaligned_suffix(annotation)
  if annotation and annotation.misaligned then
    return " (+1 misaligned)"
  end
  return ""
end

-- Format one row of the view. `block` is the block annotation at this row
-- (if the row starts a block), `line` is the per-instruction L0 annotation,
-- and `mode` is one of "off", "both", "l1", or "l0".
local function format_view_base(block, line, mode)
  if mode == "off" then
    return nil
  end

  if mode == "both" then
    if block and line and not block.single_instruction and block.latency0 and block.latency1 then
      return "L0 "
        .. short_format(line)
        .. misaligned_suffix(line)
        .. " \194\183 block "
        .. short_format(block.latency0)
        .. " \194\183 L1 "
        .. short_format(block.latency1)
        .. " cyc"
    elseif block then
      if block.latency0 and block.latency1 then
        return "L0 "
          .. short_format(block.latency0)
          .. misaligned_suffix(block.latency0)
          .. " \194\183 L1 "
          .. short_format(block.latency1)
          .. " cyc"
      elseif block.latency0 then
        return "L0 "
          .. short_format(block.latency0)
          .. misaligned_suffix(block.latency0)
          .. " cyc"
      elseif block.latency1 then
        return "L1 " .. short_format(block.latency1) .. " cyc"
      end
    elseif line then
      return "L0 " .. short_format(line) .. misaligned_suffix(line) .. " cyc"
    end
  elseif mode == "l0" then
    if block and line and not block.single_instruction then
      return "L0 "
        .. short_format(line)
        .. misaligned_suffix(line)
        .. " \194\183 block "
        .. short_format(block)
        .. " cyc"
    elseif block then
      return "L0 " .. short_format(block) .. misaligned_suffix(block) .. " cyc"
    elseif line then
      return "L0 " .. short_format(line) .. misaligned_suffix(line) .. " cyc"
    end
  elseif mode == "l1" then
    if block and line and not block.single_instruction then
      return "L1 " .. short_format(line)
        .. " \194\183 block " .. short_format(block) .. " cyc"
    elseif block then
      return "L1 " .. short_format(block) .. " cyc"
    elseif line then
      return "L1 " .. short_format(line) .. " cyc"
    end
  end

  return nil
end

function M.format_view(block, line, mode)
  local text = format_view_base(block, line, mode)
  if not text then
    return nil
  end
  if (block and block.no_entry) or (line and line.no_entry) then
    text = text .. " (no known entry)"
  end
  return text
end

function M.format_view_parts(block, line, mode)
  local text = M.format_view(block, line, mode)
  if not text then
    return nil
  end
  local marker = " (+1 misaligned)"
  local start = text:find(marker, 1, true)
  if not start then
    return { { text, "DisasmCycles" } }
  end
  local parts = {}
  local before = text:sub(1, start - 1)
  if before ~= "" then
    parts[#parts + 1] = { before, "DisasmCycles" }
  end
  parts[#parts + 1] = { marker, "DisasmCyclesMisaligned" }
  local after = text:sub(start + #marker)
  if after ~= "" then
    parts[#parts + 1] = { after, "DisasmCycles" }
  end
  return parts
end

function M.compute(lines, opts)
  opts = opts or {}
  local sizes = opts.sizes or {}
  local is_flash = opts.is_flash or function(addr)
    return addr < 0x4000
  end

  local instructions = {}
  local function_id = 0
  local section = nil
  local new_function = false

  for row, line in ipairs(lines or {}) do
    local section_name = line:match("^Disassembly of section%s+(.+):%s*$")
    if section_name then
      section = section_name
      new_function = true
    else
      local function_name = line:match("^%x+%s+<(.+)>:%s*$")
      if function_name then
        function_id = function_id + 1
        new_function = true
      else
        local source_function = line:match("^%S+%(%):%s*$")
        if source_function then
          function_id = function_id + 1
          new_function = true
        else
          local insn = parse_line(line, row)
          if insn then
            if not insn.size then
              insn.size = sizes[insn.addr]
            end
            insn.function_id = function_id
            insn.section = section
            insn.is_function_start = new_function
            new_function = false
            instructions[#instructions + 1] = insn
          end
        end
      end
    end
  end

  -- Most rows get a size from the raw-insn analysis output.  For the rest,
  -- the address of the next instruction is a reliable fallback inside a
  -- function; the last instruction of a function falls back to the usual
  -- 4-byte encoding unless the mnemonic/directive says otherwise.
  for i, insn in ipairs(instructions) do
    if not insn.size then
      local next_insn = instructions[i + 1]
      if next_insn then
        local diff = next_insn.addr - insn.addr
        if diff == 2 or diff == 4 then
          insn.size = diff
        end
      end
    end
    if not insn.size and not insn.is_data then
      insn.size = 4
    end
    if insn.size and not insn.is_data and insn.size ~= 2 and insn.size ~= 4 then
      insn.size = 4
    end
  end

  local targets = {}
  local target_sources = {}
  local addr_to_insn = {}
  for _, insn in ipairs(instructions) do
    if insn.size then
      addr_to_insn[insn.addr] = insn
      if (insn.kind == "cond" or insn.kind == "uncond") and insn.target then
        targets[insn.target] = true
        local sources = target_sources[insn.target]
        if not sources then
          sources = {}
          target_sources[insn.target] = sources
        end
        sources[#sources + 1] = insn
      end
    end
  end

  local blocks = {}
  local addr_to_block = {}
  local current = nil
  local prev = nil

  local function start_block(insn, reason)
    current = {
      start_addr = insn.addr,
      end_addr = insn.addr,
      start_row = insn.row,
      start_index = nil,
      end_index = nil,
      function_id = insn.function_id,
      section = insn.section,
      is_function_start = insn.is_function_start or false,
      start_reason = reason or "entry",
      instructions = {},
    }
    blocks[#blocks + 1] = current
    current.index = #blocks
    addr_to_block[insn.addr] = current
  end

  for i, insn in ipairs(instructions) do
    if not insn.size then
      -- An unparseable data directive: it still breaks the fallthrough.
      current = nil
      prev = insn
    else
      local need_start = false
      local start_reason
      if not current then
        need_start = true
        if targets[insn.addr] then
          start_reason = describe_target_sources(target_sources[insn.addr])
        elseif insn.is_function_start then
          start_reason = "function entry"
        elseif prev and prev.call then
          start_reason = "return from " .. prev.mnemonic .. " " .. format_hex(prev.addr)
        elseif prev and prev.kind then
          start_reason = (prev.kind == "cond" and "fallthrough after " or "after ")
            .. prev.mnemonic
            .. " "
            .. format_hex(prev.addr)
        elseif prev and prev.is_data then
          start_reason = "after data"
        else
          start_reason = "entry"
        end
      elseif current.start_addr == insn.addr then
        need_start = false
      elseif insn.function_id ~= current.function_id or insn.section ~= current.section then
        need_start = true
        start_reason = "function entry"
      elseif targets[insn.addr] then
        need_start = true
        start_reason = describe_target_sources(target_sources[insn.addr])
      elseif prev and prev.call then
        need_start = true
        start_reason = "return from " .. prev.mnemonic .. " " .. format_hex(prev.addr)
      elseif prev and prev.kind then
        need_start = true
        start_reason = (prev.kind == "cond" and "fallthrough after " or "after ")
          .. prev.mnemonic
          .. " "
          .. format_hex(prev.addr)
      elseif prev and prev.size and insn.addr ~= prev.addr + prev.size then
        need_start = true
        start_reason = "after gap"
      end

      if need_start then
        start_block(insn, start_reason)
        current.start_index = i
      end

      current.instructions[#current.instructions + 1] = insn
      current.end_index = i
      current.end_addr = insn.addr + insn.size
      if insn.kind then
        current.terminator = insn
        current = nil
      end
      prev = insn
    end
  end

  for i, block in ipairs(blocks) do
    local next_insn = instructions[block.end_index + 1]
    if next_insn
      and next_insn.size
      and next_insn.addr == block.end_addr
      and next_insn.function_id == block.function_id
      and next_insn.section == block.section
    then
      block.next_block = addr_to_block[next_insn.addr]
    end
    if block.next_block then
      block.next_index = block.next_block.index
    end
    if block.terminator and block.terminator.target then
      block.taken_block = addr_to_block[block.terminator.target]
      if block.taken_block then
        block.taken_index = block.taken_block.index
      end
    end

    local term = block.terminator
    if term then
      if term.kind == "cond" then
        block.end_reason = "conditional " .. term.mnemonic
      elseif term.kind == "uncond" then
        block.end_reason = term.call and ("call " .. term.mnemonic) or ("jump " .. term.mnemonic)
      else
        block.end_reason = term.call and ("call " .. term.mnemonic)
          or (term.mnemonic .. " (indirect)")
      end
    elseif not next_insn then
      block.end_reason = "end of code"
    elseif next_insn.function_id ~= block.function_id then
      block.end_reason = "function end"
    elseif next_insn.section ~= block.section then
      block.end_reason = "section end"
    elseif not next_insn.size then
      block.end_reason = "before data"
    elseif targets[next_insn.addr] then
      block.end_reason = "next is target " .. format_hex(next_insn.addr)
    elseif next_insn.addr ~= block.end_addr then
      block.end_reason = "before gap"
    else
      block.end_reason = "fallthrough"
    end

    blocks[i] = block
  end

  local entries = {}
  local queue = {}

  local function add_entry(block_index, entry)
    if not block_index then
      return
    end
    local key = entry_key(entry)
    entries[block_index] = entries[block_index] or {}
    if not entries[block_index][key] then
      entries[block_index][key] = entry
      queue[#queue + 1] = { block_index = block_index, entry = entry }
    end
  end

  for block_index, block in ipairs(blocks) do
    if block.is_function_start then
      add_entry(block_index, { off = block.start_addr % 4, carry = 0, seq = false })
    end
  end

  local queue_index = 1
  while queue_index <= #queue do
    local item = queue[queue_index]
    queue_index = queue_index + 1
    local block = blocks[item.block_index]
    local result = simulate_block(block, item.entry, {
      latency = opts.latency,
      is_flash = is_flash,
      data_is_flash = opts.data_is_flash,
    })

    local term = block.terminator
    if term then
      if (term.kind == "cond" or term.kind == "uncond") and block.taken_index then
        add_entry(block.taken_index, taken_entry(term, term.target, is_flash))
      end
      if term.call and block.next_index then
        add_entry(block.next_index, {
          off = block.next_block.start_addr % 4,
          carry = 0,
          seq = false,
        })
      end
      if term.kind == "cond" and block.next_index then
        add_entry(block.next_index, {
          off = block.next_block.start_addr % 4,
          carry = result.carry_out,
          seq = true,
        })
      end
    elseif block.next_index then
      add_entry(block.next_index, {
        off = block.next_block.start_addr % 4,
        carry = result.carry_out,
        seq = true,
      })
    end
  end

  -- Annotate blocks with no statically known entry too, but label the cold
  -- cost explicitly instead of implying it is a reachable path.
  for block_index, block in ipairs(blocks) do
    local block_entries = entries[block_index]
    if not block_entries or not next(block_entries) then
      local has_code = false
      for _, insn in ipairs(block.instructions) do
        if not insn.is_data then
          has_code = true
          break
        end
      end
      if has_code then
        local entry = {
          off = block.start_addr % 4,
          carry = 0,
          seq = false,
          no_entry = true,
        }
        entries[block_index] = { [entry_key(entry)] = entry }
      end
    end
  end

  local annotations = {}
  local line_annotations = {}
  for block_index, block in ipairs(blocks) do
    local block_entries = entries[block_index]
    if block_entries and next(block_entries) then
      local totals = {}
      local takens = {}
      local fallthroughs = {}
      local block_misaligned = false
      local block_no_entry = false
      for _, entry in pairs(block_entries) do
        if entry.no_entry then
          block_no_entry = true
        end
        local result = simulate_block(block, entry, {
          latency = opts.latency,
          is_flash = is_flash,
          data_is_flash = opts.data_is_flash,
        })
        if result.total then
          totals[#totals + 1] = result.total
        end
        if result.taken then
          takens[#takens + 1] = result.taken
        end
        if result.fallthrough then
          fallthroughs[#fallthroughs + 1] = result.fallthrough
        end
        if result.line_costs then
          for i, line in ipairs(result.line_costs) do
            local row = block.instructions[i].row
            local annotation = line_annotations[row]
            if not annotation then
              annotation = { totals = {}, takens = {}, fallthroughs = {} }
              line_annotations[row] = annotation
            end
            if line.misaligned then
              annotation.misaligned = true
              block_misaligned = true
            end
            if entry.no_entry then
              annotation.no_entry = true
            end
            if line.total then
              annotation.totals[#annotation.totals + 1] = line.total
            end
            if line.taken then
              annotation.takens[#annotation.takens + 1] = line.taken
            end
            if line.fallthrough then
              annotation.fallthroughs[#annotation.fallthroughs + 1] = line.fallthrough
            end
          end
        end
      end

      local kind
      if block.terminator then
        kind = block.terminator.kind == "cond" and "conditional" or "taken"
      else
        kind = "plain"
      end

      local annotation = {
        kind = kind,
        end_row = block.instructions[#block.instructions].row,
        instruction_count = #block.instructions,
        misaligned = block_misaligned,
        no_entry = block_no_entry,
        start_reason = block.start_reason,
        end_reason = block.end_reason,
      }
      if kind == "conditional" then
        annotation.taken_values = sorted_unique(takens)
        annotation.fallthrough_values = sorted_unique(fallthroughs)
        annotation.taken_min, annotation.taken_max = minmax(annotation.taken_values)
        annotation.fallthrough_min, annotation.fallthrough_max = minmax(annotation.fallthrough_values)
      elseif kind == "taken" then
        annotation.taken_values = sorted_unique(takens)
        annotation.taken_min, annotation.taken_max = minmax(annotation.taken_values)
      else
        annotation.total_values = sorted_unique(totals)
        annotation.total_min, annotation.total_max = minmax(annotation.total_values)
      end
      annotation.variable = (annotation.taken_values and #annotation.taken_values > 1)
        or (annotation.fallthrough_values and #annotation.fallthrough_values > 1)
        or (annotation.total_values and #annotation.total_values > 1)
        or false
      annotation.single_instruction = #block.instructions == 1
      annotations[block.start_row] = annotation
    end
  end

  for row, annotation in pairs(line_annotations) do
    local final = { misaligned = annotation.misaligned, no_entry = annotation.no_entry }
    if #annotation.takens > 0 and #annotation.fallthroughs > 0 then
      final.kind = "conditional"
      final.taken_values = sorted_unique(annotation.takens)
      final.fallthrough_values = sorted_unique(annotation.fallthroughs)
      final.taken_min, final.taken_max = minmax(final.taken_values)
      final.fallthrough_min, final.fallthrough_max = minmax(final.fallthrough_values)
    elseif #annotation.takens > 0 then
      final.kind = "taken"
      final.taken_values = sorted_unique(annotation.takens)
      final.taken_min, final.taken_max = minmax(final.taken_values)
    else
      final.kind = "plain"
      final.total_values = sorted_unique(annotation.totals)
      final.total_min, final.total_max = minmax(final.total_values)
    end
    line_annotations[row] = final
  end

  return {
    annotations = annotations,
    line_annotations = line_annotations,
    blocks = blocks,
    instructions = instructions,
    targets = targets,
    addr_to_insn = addr_to_insn,
  }
end

return M
