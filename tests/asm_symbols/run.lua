local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local symbols = require("asm_symbols")

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

test("parse posix nm output", function()
  local out = table.concat({
    "delay T 9a",
    "lool T c8 4",
    "CLOCK_SPEED D 20000000",
    "_sidata A e8",
    "__global_pointer$ D 20000010",
    "",
  }, "\n")
  local parsed = symbols.parse_nm(out)
  eq(#parsed, 5)
  eq(parsed[1], { name = "delay", type = "T", address = "9a" })
  eq(parsed[2], { name = "lool", type = "T", address = "c8", size = 4 })
  eq(parsed[4], { name = "_sidata", type = "A", address = "e8" })
  eq(parsed[5].name, "__global_pointer$")
end)

test("parse skips blank, undefined and malformed lines", function()
  local out = "foo U\n\n???\nbar T 10\n"
  local parsed = symbols.parse_nm(out)
  eq(#parsed, 1)
  eq(parsed[1].name, "bar")
end)

test("item kinds follow nm types", function()
  local kind = symbols.kind_for
  eq(kind("T"), vim.lsp.protocol.CompletionItemKind.Function)
  eq(kind("w"), vim.lsp.protocol.CompletionItemKind.Function)
  eq(kind("d"), vim.lsp.protocol.CompletionItemKind.Variable)
  eq(kind("A"), vim.lsp.protocol.CompletionItemKind.Constant)
  eq(kind("?"), vim.lsp.protocol.CompletionItemKind.Text)
end)

test("to_items dedupes and inserts plain names", function()
  local items = symbols.to_items({
    { name = "delay", type = "T", address = "9a" },
    { name = "delay", type = "t", address = "aa" },
    { name = "CLOCK_SPEED", type = "D", address = "20000000" },
  }, "/proj/out/firmware.elf")
  eq(#items, 2)
  eq(items[1].label, "delay")
  eq(items[1].kind, vim.lsp.protocol.CompletionItemKind.Function)
  eq(items[1].insertText, "delay")
  eq(items[1].insertTextFormat, vim.lsp.protocol.InsertTextFormat.PlainText)
  ok(items[1].detail:find("T", 1, true) ~= nil, "detail mentions the nm type")
  ok(items[1].detail:find("0x9a", 1, true) ~= nil, "detail mentions the address")
end)

test("newest ELF wins", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/old.elf")
  vim.fn.writefile({ "" }, tmp .. "/out/new.elf")
  local old, new = tmp .. "/out/old.elf", tmp .. "/out/new.elf"
  vim.uv.fs_utime(old, 1000, 1000)
  vim.uv.fs_utime(new, 2000, 2000)
  eq(symbols.find_newest_elf(tmp .. "/src/main.s", nil), vim.fs.normalize(new))
  vim.fn.delete(tmp, "rf")
end)

test("configured ELF overrides newest", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/old.elf")
  vim.fn.writefile({ "" }, tmp .. "/out/new.elf")
  vim.uv.fs_utime(tmp .. "/out/old.elf", 1000, 1000)
  vim.uv.fs_utime(tmp .. "/out/new.elf", 2000, 2000)
  eq(
    symbols.find_newest_elf(tmp .. "/src/main.s", tmp .. "/out/old.elf"),
    vim.fs.normalize(tmp .. "/out/old.elf")
  )
  vim.fn.delete(tmp, "rf")
end)

test("resolve_nm honors an explicit executable and rejects a missing one", function()
  local argv = symbols.resolve_nm("nm")
  eq(argv, { "nm" })
  eq(symbols.resolve_nm("definitely-not-an-nm"), nil)
end)

test("no ELF yields an empty completion list", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/main.s")
  local called
  symbols.new({}):get_completions({ bufnr = buf }, function(result)
    called = result
  end)
  eq(called, { items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

test("missing nm yields an empty completion list", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/f.elf")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/main.s")
  local called
  symbols.new({ nm = "definitely-not-an-nm" }):get_completions({ bufnr = buf }, function(result)
    called = result
  end)
  eq(called, { items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

print(string.format("\n%d/%d passed", test_count - fail_count, test_count))
if fail_count > 0 then
  vim.cmd("cquit 1")
end