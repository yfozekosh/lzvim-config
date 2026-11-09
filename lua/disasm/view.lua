local cycles = require("disasm.cycles")

local M = {}

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.define_highlight(config)
  vim.api.nvim_set_hl(0, "DisasmMatch", { default = true, link = (config and config.highlight) or "Visual" })
  vim.api.nvim_set_hl(0, "DisasmCycles", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "DisasmCyclesStart", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "DisasmCyclesEnd", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "DisasmCyclesMisaligned", { default = true, link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "DisasmSize", { default = true, link = "Comment" })
end

function M.open(state)
  if win_valid(state.asm_win) then
    return true
  end
  if not win_valid(state.source_win) then
    state.source_win = vim.api.nvim_get_current_win()
  end

  local previous = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(state.source_win)
  vim.cmd("rightbelow vsplit")
  state.asm_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(previous)
  return true
end

function M.ensure_buffer(state)
  if buf_valid(state.asm_buf) then
    return state.asm_buf
  end
  state.asm_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.asm_buf, "Disassembly")
  vim.bo[state.asm_buf].buftype = "nofile"
  vim.bo[state.asm_buf].bufhidden = "wipe"
  vim.bo[state.asm_buf].swapfile = false
  vim.bo[state.asm_buf].buflisted = false
  return state.asm_buf
end

function M.set_winbar(state)
  if not win_valid(state.asm_win) then
    return
  end
  if not (state.config and state.config.winbar) then
    vim.wo[state.asm_win].winbar = ""
    return
  end
  local name = state.elf and vim.fn.fnamemodify(state.elf, ":~:.") or "disassembly"
  local modified = false
  if win_valid(state.source_win) then
    modified = vim.bo[vim.api.nvim_win_get_buf(state.source_win)].modified
  end
  local suffix = modified and " [modified]" or ""
  local latency = ""
  local mode = state.config and state.config.cycle_view or "off"
  if state.config and state.config.cycles ~= false then
    if mode == "both" then
      latency = " [L0+1]"
    elseif mode == "l1" then
      latency = " [L1]"
    elseif mode == "l0" then
      latency = " [L0]"
    end
  end
  local sizes = state.config and state.config.show_sizes and " [sizes]" or ""
  vim.wo[state.asm_win].winbar = " Disassembly: " .. name .. suffix .. latency .. sizes
end

function M.set_keymaps(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  local buf = state.asm_buf
  local base = { buffer = buf, silent = true }
  vim.keymap.set("n", "q", function()
    require("disasm").close()
  end, vim.tbl_extend("force", base, { desc = "Close disassembly" }))
  vim.keymap.set("n", "r", function()
    require("disasm").refresh()
  end, vim.tbl_extend("force", base, { desc = "Refresh disassembly" }))
  vim.keymap.set("n", "K", function()
    require("riscv_asm").hover_current()
  end, vim.tbl_extend("force", base, { desc = "Hover (RISC-V)" }))
  vim.keymap.set("n", "L", function()
    require("disasm").toggle_latency()
  end, vim.tbl_extend("force", base, { desc = "Cycle latency view" }))
  vim.keymap.set("n", "S", function()
    require("disasm").toggle_sizes()
  end, vim.tbl_extend("force", base, { desc = "Toggle instruction sizes" }))
end

function M.render(state)
  if not M.open(state) then
    return false
  end
  local buf = M.ensure_buffer(state)

  vim.api.nvim_win_set_buf(state.asm_win, buf)

  vim.wo[state.asm_win].number = true
  vim.wo[state.asm_win].relativenumber = false
  vim.wo[state.asm_win].signcolumn = "no"
  vim.wo[state.asm_win].foldcolumn = "0"
  vim.wo[state.asm_win].cursorline = true
  vim.wo[state.asm_win].wrap = false

  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.lines or {})
  vim.bo[buf].filetype = "asm"
  pcall(vim.treesitter.start, buf, "asm")
  pcall(vim.diagnostic.enable, false, { bufnr = buf })
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  M.set_winbar(state)
  M.set_keymaps(state)
  M.render_cycles(state)
  M.render_sizes(state)
  return true
end

function M.render_cycles(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  local ns = state.cycle_ns
  if not ns then
    ns = vim.api.nvim_create_namespace("disasm.cycles")
    state.cycle_ns = ns
  end
  vim.api.nvim_buf_clear_namespace(state.asm_buf, ns, 0, -1)
  if state.config and state.config.cycles == false then
    return
  end
  local mode = state.config and state.config.cycle_view or "off"
  if mode ~= "both" and mode ~= "l1" and mode ~= "l0" then
    return
  end
  local line_count = #(state.lines or {})
  local block_annotations = state.cycle_annotations or {}
  local line_annotations = state.cycle_line_annotations or {}
  local rows = {}
  local start_reasons = {}
  local end_reasons = {}
  for row, block in pairs(block_annotations) do
    rows[row] = true
    start_reasons[row] = block.start_reason or "entry"
    if block.instruction_count and block.instruction_count > 1 and block.end_row and block.end_row ~= row then
      end_reasons[block.end_row] = block.end_reason or "end"
      rows[block.end_row] = true
    else
      end_reasons[row] = block.end_reason or "end"
    end
  end
  for row in pairs(line_annotations) do
    rows[row] = true
  end

  for row in pairs(rows) do
    if row >= 1 and row <= line_count then
      local block = block_annotations[row]
      local line = line_annotations[row]
      local parts = cycles.format_view_parts(block, line, mode) or {}
      if start_reasons[row] then
        parts[#parts + 1] = { " \194\183 block start: " .. start_reasons[row], "DisasmCyclesStart" }
      end
      if end_reasons[row] then
        parts[#parts + 1] = { " \194\183 end block: " .. end_reasons[row], "DisasmCyclesEnd" }
      end

      if #parts > 0 then
        local virt_text = { { "  ; ", "DisasmCycles" } }
        for _, part in ipairs(parts) do
          virt_text[#virt_text + 1] = part
        end
        vim.api.nvim_buf_set_extmark(state.asm_buf, ns, row - 1, 0, {
          virt_text = virt_text,
          virt_text_pos = "eol",
          hl_mode = "combine",
          priority = 100,
        })
      end
    end
  end
end

function M.render_sizes(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  local ns = state.size_ns
  if not ns then
    ns = vim.api.nvim_create_namespace("disasm.sizes")
    state.size_ns = ns
  end
  vim.api.nvim_buf_clear_namespace(state.asm_buf, ns, 0, -1)
  if not (state.config and state.config.show_sizes) then
    return
  end
  local row_sizes = cycles.row_sizes(state.lines, state.cycle_sizes)
  local line_count = #(state.lines or {})
  for row, size in pairs(row_sizes) do
    if row >= 1 and row <= line_count then
      local line = state.lines[row]
      local _, match_end = line:find("^%s*[0-9a-fA-F]+")
      if match_end then
        vim.api.nvim_buf_set_extmark(state.asm_buf, ns, row - 1, match_end, {
          virt_text = { { "(" .. size .. ")", "DisasmSize" } },
          virt_text_pos = "inline",
          priority = 100,
        })
      end
    end
  end
end

function M.clear(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.asm_buf, state.ns, 0, -1)
end

function M.highlight(state, ranges)
  M.clear(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  for _, range in ipairs(ranges or {}) do
    for row = range[1], range[2] do
      vim.api.nvim_buf_set_extmark(state.asm_buf, state.ns, row - 1, 0, {
        line_hl_group = "DisasmMatch",
        priority = 200,
      })
    end
  end
end

function M.scroll_to(state, row)
  if not win_valid(state.asm_win) then
    return
  end
  vim.api.nvim_win_set_cursor(state.asm_win, { row, 0 })
  vim.api.nvim_win_call(state.asm_win, function()
    vim.cmd("normal! zz")
  end)
end

function M.close(state)
  if win_valid(state.asm_win) then
    vim.api.nvim_win_close(state.asm_win, true)
  end
  state.asm_win = nil
  state.asm_buf = nil
end

return M
