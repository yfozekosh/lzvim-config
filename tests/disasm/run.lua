local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local parser = require("disasm.parser")
local cycles = require("disasm.cycles")

local fail_count = 0
local test_count = 0

local function deep_eq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function show(v)
  return vim.inspect(v):gsub("%s+", " ")
end

local function eq(actual, expected, msg)
  if not deep_eq(actual, expected) then
    error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "values differ", show(expected), show(actual)), 2)
  end
end

local function ok(cond, msg)
  if not cond then
    error(msg or "assertion failed", 2)
  end
end

local function test(name, fn)
  test_count = test_count + 1
  local success, err = pcall(fn)
  if success then
    print("ok " .. name)
  else
    fail_count = fail_count + 1
    print("not ok " .. name)
    print("  " .. tostring(err):gsub("\n", "\n  "))
  end
end

local fixture = vim.fn.readfile(root .. "/tests/disasm/fixtures/riscv_objdump.txt")
local function resolve_identity(path)
  return vim.fs.normalize(path)
end

test("parses markers and rows", function()
  local result = parser.parse(fixture, { resolve_path = resolve_identity })
  ok(result.has_markers, "expected has_markers")
  eq(result.index["/home/proj/src/boot.s"][13].first_row, 7, "boot.s:13 first row")
  eq(#result.index["/home/proj/src/test.c"][13].ranges, 2, "test.c:13 range count")
  eq(result.index["/home/proj/src/test.c"][13].first_row, 15, "test.c:13 first row")
end)

test("disjoint ranges", function()
  local result = parser.parse(fixture, { resolve_path = resolve_identity })
  eq(result.index["/home/proj/src/test.c"][13].ranges, { { 15, 16 }, { 18, 19 } }, "test.c:13 ranges")
end)

test("unmarked function stays unmapped", function()
  local result = parser.parse(fixture, { resolve_path = resolve_identity })
  for path, lines in pairs(result.index) do
    for line, entry in pairs(lines) do
      for _, range in ipairs(entry.ranges) do
        ok(
          not (range[1] <= 31 and range[2] >= 30),
          string.format("unmarked rows 30-31 leaked into %s:%d", path, line)
        )
      end
    end
  end
end)

test("no markers", function()
  local result = parser.parse({
    "Disassembly of section .text:",
    "",
    "00000000 <_start>:",
    "   0:\tnop",
  }, { resolve_path = resolve_identity })
  eq(result.has_markers, false, "has_markers")
  eq(next(result.index), nil, "index is empty")
end)

test("relative path is resolved", function()
  local result = parser.parse({
    "src/test.c:10",
    "  b0:\tj",
  }, {
    resolve_path = function(path)
      return "/abs/" .. path
    end,
  })
  ok(result.index["/abs/src/test.c"], "relative marker path resolved")
  eq(result.index["/abs/src/test.c"][10].first_row, 1, "instruction row")
end)

test("function and section headers are kept", function()
  local result = parser.parse(fixture, { resolve_path = resolve_identity })
  local seen = {}
  for _, line in ipairs(result.lines) do
    seen[line] = true
  end
  ok(seen["Disassembly of section .text:"], "section header kept")
  ok(seen["0000009a <main>:"], "address header kept")
  ok(seen["main():"], "source function header kept")
  ok(not seen["/home/proj/src/test.c:13 (discriminator 2)"], "marker lines removed")
end)

local config = require("disasm.config")

test("defaults", function()
  local c = config.setup({})
  eq(c.args, { "-d", "-l", "-C", "--no-show-raw-insn" }, "args")
  eq(c.auto_scroll, true, "auto_scroll")
end)

test("string objdump", function()
  local c = config.setup({ objdump = "cat" })
  local argv = config.resolve_objdump(c)
  eq(argv, { "cat" }, "argv")
end)

test("table objdump", function()
  local c = config.setup({ objdump = { "sh", "-c" } })
  local argv = config.resolve_objdump(c)
  eq(argv, { "sh", "-c" }, "argv")
end)

test("resolver absolute", function()
  local tmp = vim.fn.tempname()
  vim.fn.writefile({ "x" }, tmp)
  local elf = tmp .. ".elf"
  local resolver = config.make_path_resolver(elf)
  eq(resolver(tmp), vim.fs.normalize(tmp), "absolute path")
  vim.fn.delete(tmp)
end)

test("resolver relative", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "x" }, tmp .. "/src/x.c")
  local elf = tmp .. "/out/f.elf"
  local resolver = config.make_path_resolver(elf)
  eq(resolver("src/x.c"), vim.fs.normalize(tmp .. "/src/x.c"), "relative path")
  vim.fn.delete(tmp, "rf")
end)

test("resolver prefers opened project over recorded absolute path", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/newproj/src", "p")
  vim.fn.mkdir(tmp .. "/newproj/out", "p")
  vim.fn.mkdir(tmp .. "/old/place/src", "p")
  vim.fn.writefile({ "" }, tmp .. "/newproj/Makefile")
  vim.fn.writefile({ "x" }, tmp .. "/newproj/src/x.c")
  -- The build-time path still exists, but must not win over the project copy.
  vim.fn.writefile({ "stale" }, tmp .. "/old/place/src/x.c")
  local elf = tmp .. "/newproj/out/f.elf"
  local resolver = config.make_path_resolver(elf)
  eq(
    resolver(tmp .. "/old/place/src/x.c"),
    vim.fs.normalize(tmp .. "/newproj/src/x.c"),
    "opened project path should shadow the recorded absolute path"
  )
  vim.fn.delete(tmp, "rf")
end)

test("cycle config defaults and flash range", function()
  local c = config.setup({})
  eq(c.cycles, true, "cycles")
  eq(c.cycle_view, "off", "cycle_view")
  eq(c.flash_start, 0x00000000, "flash_start")
  eq(c.flash_end, 0x00004000, "flash_end")
  eq(c.data_is_flash, false, "data_is_flash")
  local is_flash = config.make_flash_check(c)
  ok(is_flash(0x00001000), "flash address")
  ok(not is_flash(0x00004000), "flash_end is exclusive")
  ok(not is_flash(0x20000000), "SRAM address is not flash")
end)

test("cycle raw objdump args", function()
  eq(
    config.raw_args({ "-d", "--no-show-raw-insn", "-l", "-C" }),
    { "-d", "-l", "-C", "--show-raw-insn" },
    "raw args"
  )
end)

test("cycle sizes from raw instructions", function()
  local sizes = cycles.parse_sizes({
    "   0:\t20001117          \tauipc\tsp,0x20001",
    "   4:\t0001              \tnop",
    "   6:\taddi\ta0,a0,-1",
    "   8:\t00000013          \t.word\t0x00000013",
  })
  eq(sizes, { [0] = 4, [4] = 2, [8] = 4 }, "raw sizes")
end)

test("cycle latency 0 block totals", function()
  local result = cycles.compute({
    "00000000 <f>:",
    "   0:\t00000013\t\tnop",
    "   4:\t00a12023\t\tsw\ta0,0(sp)",
    "   8:\t00000063\t\tbeqz\ta0,c <f+0xc>",
    "   c:\t00000067\t\tret",
  }, { latency = 0 })
  eq(#result.blocks, 2, "block count")
  eq(cycles.format(result.annotations[2]), "taken 6 / fallthrough 4 cyc", "conditional block")
  eq(cycles.format(result.annotations[5]), "3 cyc", "return block")
end)

test("cycle latency 0 alignment waiver", function()
  local result = cycles.compute({
    "00000000 <f>:",
    "   0:\t0001\t\tc.nop",
    "   2:\t00000013\t\tnop",
  }, { latency = 0 })
  eq(cycles.format(result.annotations[2]), "2 cyc", "sequential 32-bit instruction gets waiver")
end)

test("cycle latency 0 fresh 4k+2 block has no waiver", function()
  local result = cycles.compute({
    "00000000 <f>:",
    "   0:\ta001\t\tc.j\t2 <f+0x2>",
    "   2:\t00000013\t\tnop",
  }, { latency = 0 })
  eq(cycles.format(result.annotations[2]), "3 cyc", "taken jump block")
  eq(cycles.format(result.annotations[3]), "2 cyc", "target starts without waiver")
end)

test("cycle latency 1 empty loop and fallthrough fetch state", function()
  local result = cycles.compute({
    "000001dc <bench>:",
    " 1dc:\t157d\t\taddi\ta0,a0,-1",
    " 1de:\tfd7d\t\tbnez\ta0,1dc <bench>",
    " 1e0:\t00008067\t\tret",
  }, { latency = 1 })
  eq(#result.blocks, 2, "block count")
  eq(cycles.format(result.annotations[2]), "taken 6 / fallthrough 2 cyc", "loop block")
  eq(cycles.format(result.annotations[4]), "6 cyc", "ret inherits fallthrough fetch carry")
  eq(result.blocks[1].taken_index, 1, "self-loop target")
end)

test("cycle latency 1 16-bit nop loop", function()
  local result = cycles.compute({
    "000001dc <bench>:",
    " 1dc:\t0001\t\t.short\t0x0001",
    " 1de:\t157d\t\taddi\ta0,a0,-1",
    " 1e0:\tfd75\t\tbnez\ta0,1dc <bench>",
    " 1e2:\t00008067\t\tret",
  }, { latency = 1 })
  eq(result.instructions[1].is_data, true, "data directive kept as pseudo-instruction")
  eq(result.instructions[1].size, 2, "16-bit directive size")
  eq(cycles.format(result.annotations[2]), "taken 6 / fallthrough 2 cyc", "nop16 loop block")
  eq(cycles.format(result.annotations[5]), "6 cyc", "nop16 ret block")
end)

test("cycle latency 1 32-bit nop loop", function()
  local result = cycles.compute({
    "000001dc <bench>:",
    " 1dc:\t00000013\t\t.word\t0x00000013",
    " 1e0:\t157d\t\taddi\ta0,a0,-1",
    " 1e2:\tfd6d\t\tbnez\ta0,1dc <bench>",
    " 1e4:\t00008067\t\tret",
  }, { latency = 1 })
  eq(cycles.format(result.annotations[2]), "taken 8 / fallthrough 4 cyc", "nop32 loop block")
  eq(cycles.format(result.annotations[5]), "6 cyc", "nop32 ret block")
end)

test("cycle latency 1 taken and not-taken branches", function()
  local result = cycles.compute({
    "000001f4 <bench>:",
    " 1f4:\t00d59263\t\tbne\ta1,a3,1f8 <bench+0x4>",
    " 1f8:\t157d\t\taddi\ta0,a0,-1",
    " 1fa:\tfd6d\t\tbnez\ta0,1f4 <bench>",
    " 1fc:\t00008067\t\tret",
  }, { latency = 1 })
  eq(cycles.format(result.annotations[2]), "taken 4 / fallthrough 2 cyc", "aligned 32-bit conditional")
  eq(cycles.format(result.annotations[3]), "taken 6 / fallthrough 2 cyc", "addi + bnez")
  eq(cycles.format(result.annotations[5]), "6 cyc", "ret")
end)

test("cycle latency 1 flash load extras", function()
  local result = cycles.compute({
    "00000000 <f>:",
    "   0:\t4482\t\tlw\ts1,0(sp)",
  }, { latency = 1 })
  eq(cycles.format(result.annotations[2]), "2 cyc", "16-bit load crosses no chunk")

  local straddling = cycles.compute({
    "00000000 <f>:",
    "   0:\ta001\t\tc.j\t2 <f+0x2>",
    "   2:\t00412403\t\tlw\ts0,4(sp)",
  }, { latency = 1 })
  eq(cycles.format(straddling.annotations[3]), "4 cyc", "straddling 32-bit load at fresh block start")

  local flash_data = cycles.compute({
    "00000000 <f>:",
    "   0:\t4482\t\tlw\ts1,0(sp)",
  }, { latency = 1, data_is_flash = true })
  eq(cycles.format(flash_data.annotations[2]), "4 cyc", "flash data adds two cycles")
end)

test("cycle latency 1 SRAM bypasses flash fetch", function()
  local result = cycles.compute({
    "20000000 <sram>:",
    "20000000:\t157d\t\taddi\ta0,a0,-1",
    "20000002:\tfd7d\t\tbnez\ta0,20000000 <sram>",
    "20000004:\t00008067\t\tret",
  }, {
    latency = 1,
    is_flash = function(addr)
      return addr < 0x4000
    end,
  })
  eq(cycles.format(result.annotations[2]), "taken 4 / fallthrough 2 cyc", "SRAM loop")
  eq(cycles.format(result.annotations[4]), "3 cyc", "SRAM ret")
end)

test("cycle data-only block is not annotated", function()
  local result = cycles.compute({
    "00000000 <vec>:",
    "   0:\t0000006f\t\tj\t8 <vec+0x8>",
    "   4:\t00000013\t\t.word\t0x00000013",
    "   8:\t00008067\t\tret",
  }, { latency = 0 })
  eq(#result.blocks, 3, "block count")
  ok(result.annotations[2] ~= nil, "jump block annotated")
  eq(result.annotations[3], nil, "data-only block skipped")
  ok(result.annotations[4] ~= nil, "target block annotated")
end)

test("cycle unreachable code gets no-entry fallback", function()
  local result = cycles.compute({
    "00000000 <f>:",
    "   0:\t0000006f\t\tj\t8 <f+0x8>",
    "   4:\t00000013\t\tnop",
    "   8:\t00008067\t\tret",
  }, { latency = 0 })
  ok(result.annotations[2] ~= nil, "entry block annotated")
  ok(result.annotations[3] ~= nil, "unreachable block annotated via fallback")
  eq(result.annotations[3].no_entry, true, "unreachable block marked no_entry")
  eq(result.annotations[3].start_reason, "after j 0", "unreachable start reason")
  eq(result.annotations[3].end_reason, "next is target 8", "unreachable end reason")
  eq(
    cycles.format_view(result.annotations[3], nil, "l0"),
    "L0 1 cyc (no known entry)",
    "unreachable fallback label"
  )
  ok(result.annotations[4] ~= nil, "target block annotated")
end)

test("cycle latency 0 per-line costs", function()
  local result = cycles.compute({
    "0000009c <delay>:",
    "  9c:\t00000063\t\tbeqz\ta0,a8 <delay+0xc>",
    "  a0:\t00000013\t\tnop",
    "  a4:\t00000063\t\tbeqz\ta0,9c <delay>",
    "  a8:\t00000067\t\tret",
  }, { latency = 0 })
  eq(cycles.format(result.annotations[2]), "taken 3 / fallthrough 1 cyc", "single-instruction conditional block")
  eq(result.annotations[2].single_instruction, true, "single-instruction marker")
  eq(cycles.format(result.annotations[3]), "taken 4 / fallthrough 2 cyc", "multi-instruction block total")
  eq(result.annotations[3].single_instruction, false, "multi-instruction marker")
  eq(result.annotations[3].end_row, 4, "multi-instruction block end row")
  eq(result.annotations[3].instruction_count, 2, "multi-instruction block instruction count")
  eq(result.annotations[3].start_reason, "fallthrough after beqz 9c", "block start reason")
  eq(result.annotations[3].end_reason, "conditional beqz", "block end reason")
  eq(result.annotations[5].start_reason, "target of beqz 9c", "target block start reason")
  eq(result.annotations[5].end_reason, "ret (indirect)", "ret block end reason")
  eq(cycles.format_line(result.line_annotations[3]), "L0 1", "plain line cost")
  eq(cycles.format_line(result.line_annotations[4]), "L0 3/1", "conditional terminator line cost")
  eq(cycles.format_line(result.line_annotations[5]), "L0 3", "return line cost")
end)

test("cycle latency 0 per-line alignment costs", function()
  local waived = cycles.compute({
    "00000000 <f>:",
    "   0:\t0001\t\tc.nop",
    "   2:\t00000013\t\tnop",
  }, { latency = 0 })
  eq(cycles.format_line(waived.line_annotations[3]), "L0 1", "waived 32-bit line cost")
  eq(waived.line_annotations[3].misaligned, nil, "waived line is not marked misaligned")
  eq(cycles.format(waived.annotations[2]), "2 cyc", "waived block total")
  eq(
    cycles.format_view(waived.annotations[2], waived.line_annotations[3], "l0"),
    "L0 1 · block 2 cyc",
    "waived line view"
  )

  local fresh = cycles.compute({
    "00000000 <f>:",
    "   0:\t0000006f\t\tj\t2 <f+0x2>",
    "   2:\t00000013\t\tnop",
  }, { latency = 0 })
  eq(cycles.format_line(fresh.line_annotations[3]), "L0 2", "fresh 4k+2 line cost")
  eq(fresh.line_annotations[3].misaligned, true, "fresh line is marked misaligned")
  eq(cycles.format(fresh.annotations[3]), "2 cyc", "fresh 4k+2 block total")
  eq(fresh.annotations[3].misaligned, true, "fresh block is marked misaligned")
  eq(
    cycles.format_view(fresh.annotations[3], fresh.line_annotations[3], "l0"),
    "L0 2 (+1 misaligned) cyc",
    "fresh 4k+2 view"
  )
end)

test("cycle formatting discrete values", function()
  eq(
    cycles.format({
      kind = "conditional",
      taken_min = 4,
      taken_max = 6,
      taken_values = { 4, 6 },
      fallthrough_min = 2,
      fallthrough_max = 4,
      fallthrough_values = { 2, 4 },
    }),
    "taken 4 or 6 / fallthrough 2 or 4 cyc",
    "range"
  )
  eq(
    cycles.format({ kind = "taken", taken_min = 4, taken_max = 6, taken_values = { 4, 6 } }),
    "4 or 6 cyc",
    "ret range lists discrete values"
  )
end)

test("cycle compare formatting", function()
  eq(
    cycles.format_compare(
      {
        kind = "conditional",
        taken_min = 4,
        taken_max = 6,
        taken_values = { 4, 6 },
        fallthrough_min = 2,
        fallthrough_max = 4,
        fallthrough_values = { 2, 4 },
      },
      {
        kind = "conditional",
        taken_min = 6,
        taken_max = 6,
        taken_values = { 6 },
        fallthrough_min = 2,
        fallthrough_max = 2,
        fallthrough_values = { 2 },
      }
    ),
    "L0 (4 or 6)/(2 or 4) · L1 6/2 cyc",
    "conditional compare"
  )
  eq(
    cycles.format_compare(
      { kind = "plain", total_min = 2, total_max = 2, total_values = { 2 } },
      { kind = "plain", total_min = 6, total_max = 6, total_values = { 6 } }
    ),
    "L0 2 · L1 6 cyc",
    "plain compare"
  )
end)

test("cycle view formatting", function()
  local line = { kind = "plain", total_min = 1, total_max = 1, total_values = { 1 } }
  local cond0 = {
    kind = "conditional",
    taken_min = 4,
    taken_max = 4,
    taken_values = { 4 },
    fallthrough_min = 2,
    fallthrough_max = 2,
    fallthrough_values = { 2 },
    single_instruction = false,
  }
  local cond1 = {
    kind = "conditional",
    taken_min = 6,
    taken_max = 6,
    taken_values = { 6 },
    fallthrough_min = 2,
    fallthrough_max = 2,
    fallthrough_values = { 2 },
    single_instruction = false,
  }
  local both = {
    compare = true,
    latency0 = cond0,
    latency1 = cond1,
    single_instruction = false,
  }
  eq(cycles.format_view(both, line, "both"), "L0 1 · block 4/2 · L1 6/2 cyc", "both multi")
  eq(
    cycles.format_view({
      compare = true,
      latency0 = cond0,
      latency1 = cond1,
      single_instruction = true,
    }, nil, "both"),
    "L0 4/2 · L1 6/2 cyc",
    "both single"
  )
  eq(cycles.format_view(nil, line, "both"), "L0 1 cyc", "both line")
  eq(cycles.format_view(cond0, line, "l0"), "L0 1 · block 4/2 cyc", "l0 multi")
  eq(
    cycles.format_view(vim.tbl_extend("force", { single_instruction = true }, cond0), nil, "l0"),
    "L0 4/2 cyc",
    "l0 single"
  )
  eq(cycles.format_view(nil, line, "l0"), "L0 1 cyc", "l0 line")
  eq(cycles.format_view(cond1, nil, "l1"), "L1 6/2 cyc", "l1 block")
  eq(cycles.format_view(nil, line, "l1"), "L1 1 cyc", "l1 line")
  eq(cycles.format_view(both, line, "off"), nil, "off")
end)

test("cycle view parts misaligned", function()
  local line = {
    kind = "plain",
    total_min = 2,
    total_max = 2,
    total_values = { 2 },
    misaligned = true,
  }
  eq(cycles.format_view_parts(nil, line, "l0"), {
    { "L0 2", "DisasmCycles" },
    { " (+1 misaligned)", "DisasmCyclesMisaligned" },
    { " cyc", "DisasmCycles" },
  }, "misaligned chunks")
  eq(cycles.format_view_parts(nil, line, "off"), nil, "off chunks")
end)

test("cycle row sizes", function()
  local raw = cycles.row_sizes({
    "   0:\t0001\t\tc.nop",
    "   2:\t00000013\t\tnop",
    "   6:\t00008067\t\tret",
  })
  eq(raw[1], 2, "raw c.nop size")
  eq(raw[2], 4, "raw nop size")
  eq(raw[3], 4, "raw ret size")

  local inferred = cycles.row_sizes({
    "   0:\tc.nop",
    "   2:\tnop",
    "   6:\tret",
  })
  eq(inferred[1], 2, "inferred c.nop size")
  eq(inferred[2], 4, "inferred nop size")
  eq(inferred[3], 4, "inferred ret size")
end)

test("compressed nop relabel", function()
  local lines = {
    "00000000 <f>:",
    "   0:\t0001\t\tnop",
    "   2:\t00000013\t\tnop",
    "   6:\t00008067\t\tret",
  }
  local result = cycles.relabel_compressed(lines, {})
  eq(result[1], "00000000 <f>:")
  eq(result[2], "   0:\t0001\t\tc.nop")
  eq(result[3], "   2:\t00000013\t\tnop")
  eq(result[4], "   6:\t00008067\t\tret")

  local plain = { "   0:\tnop", "   2:\tnop", "   6:\tret" }
  local result2 = cycles.relabel_compressed(plain, {})
  eq(result2[1], "   0:\tc.nop")
  eq(result2[2], "   2:\tnop")
  eq(result2[3], "   6:\tret")
end)

test("cycle latency 1 per-line costs", function()
  local loop = cycles.compute({
    "000001dc <bench>:",
    " 1dc:\t157d\t\taddi\ta0,a0,-1",
    " 1de:\tfd7d\t\tbnez\ta0,1dc <bench>",
  }, { latency = 1 })
  eq(loop.annotations[2].taken_values, { 6 }, "loop taken")
  eq(loop.annotations[2].fallthrough_values, { 2 }, "loop fallthrough")
  eq(cycles.format_view(nil, loop.line_annotations[2], "l1"), "L1 0 cyc", "addi line fetch")
  eq(cycles.format_view(nil, loop.line_annotations[3], "l1"), "L1 6/2 cyc", "bnez line fetch")

  local long = cycles.compute({
    "000001dc <bench>:",
    " 1dc:\t00000013\t\tnop",
    " 1e0:\t157d\t\taddi\ta0,a0,-1",
    " 1e2:\tfd7d\t\tbnez\ta0,1dc <bench>",
  }, { latency = 1 })
  eq(long.annotations[2].taken_values, { 8 }, "long loop taken")
  eq(long.annotations[2].fallthrough_values, { 4 }, "long loop fallthrough")
  eq(cycles.format_view(nil, long.line_annotations[2], "l1"), "L1 2 cyc", "nop line fetch")
  eq(cycles.format_view(nil, long.line_annotations[3], "l1"), "L1 0 cyc", "addi line fetch")
  eq(cycles.format_view(nil, long.line_annotations[4], "l1"), "L1 6/2 cyc", "bnez line fetch")
end)

test("call creates return edge", function()
  local result = cycles.compute({
    "00000000 <main>:",
    "   0:\t000000ef\t\tjal\t8 <delay>",
    "   4:\t00000013\t\tnop",
    "   8:\t00008067\t\tret",
  }, { latency = 0 })
  ok(result.annotations[3] ~= nil, "post-call block annotated")
  eq(result.annotations[3].start_reason, "return from jal 0", "post-call start reason")
  eq(result.annotations[2].end_reason, "call jal", "call end reason")
end)

test("jump does not create return edge", function()
  local result = cycles.compute({
    "00000000 <main>:",
    "   0:\t0000006f\t\tj\t8 <main+0x8>",
    "   4:\t00000013\t\tnop",
    "   8:\t00008067\t\tret",
  }, { latency = 0 })
  ok(result.annotations[3] ~= nil, "post-jump block annotated via fallback")
  eq(result.annotations[3].no_entry, true, "post-jump block marked no_entry")
  eq(result.annotations[3].start_reason, "after j 0", "post-jump start reason")
end)

test("jalr call creates return edge", function()
  local result = cycles.compute({
    "00000000 <main>:",
    "   0:\t00000097\t\tauipc\tra,0x0",
    "   4:\t000080e7\t\tjalr\t-24(ra) # 9c <delay>",
    "   8:\t00000013\t\tnop",
    "   c:\t00008067\t\tret",
  }, { latency = 0 })
  ok(result.annotations[4] ~= nil, "post-jalr block annotated")
  eq(result.annotations[4].start_reason, "return from jalr 4", "post-jalr start reason")
  eq(result.annotations[2].end_reason, "call jalr", "jalr call end reason")
end)

test("mtrx_asm fixture annotates every instruction", function()
  local lines = vim.fn.readfile(root .. "/tests/disasm/fixtures/mtrx_asm_objdump.txt")
  local parsed = parser.parse(lines, { resolve_path = resolve_identity })
  local result = cycles.compute(parsed.lines, {
    sizes = cycles.parse_sizes(lines),
    latency = 0,
  })
  local missing = {}
  for _, insn in ipairs(result.instructions) do
    if not insn.is_data and not result.line_annotations[insn.row] then
      missing[#missing + 1] = string.format("%x %s", insn.addr, insn.mnemonic)
    end
  end
  eq(missing, {}, "every instruction annotated")
end)

print(string.format("\n%d/%d passed", test_count - fail_count, test_count))
if fail_count > 0 then
  vim.cmd("cquit 1")
end
