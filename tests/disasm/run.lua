local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local parser = require("disasm.parser")

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

print(string.format("\n%d/%d passed", test_count - fail_count, test_count))
if fail_count > 0 then
  vim.cmd("cquit 1")
end
