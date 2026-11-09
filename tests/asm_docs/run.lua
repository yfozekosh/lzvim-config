local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local docs = require("asm_docs")

local fail_count = 0
local test_count = 0

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function show(v) return vim.inspect(v):gsub("%s+", " ") end

local function eq(actual, expected, msg)
  if not deep_eq(actual, expected) then
    error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "values differ", show(expected), show(actual)), 2)
  end
end

local function ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

local function test(name, fn)
  test_count = test_count + 1
  local success, err = pcall(fn)
  if success then print("ok " .. name)
  else
    fail_count = fail_count + 1
    print("not ok " .. name)
    print("  " .. tostring(err):gsub("\n", "\n  "))
  end
end

test("preceding_comments collects contiguous comment lines", function()
  local lines = {
    "# doc one",
    "# doc two",
    "delay:",
  }
  local c = docs.preceding_comments(lines, 3)
  eq(#c, 2)
  eq(c[1], "# doc one")
  eq(c[2], "# doc two")
end)

test("preceding_comments stops at blank or code", function()
  local lines = {
    "# unrelated",
    "",
    "# doc",
    "delay:",
  }
  local c = docs.preceding_comments(lines, 4)
  eq(#c, 1)
  eq(c[1], "# doc")
end)

test("find_definition finds asm label with comments", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "# void delay(int cycles)", "delay:", "  ret" }, tmp .. "/src/delay.s")
  local def = docs.find_definition("delay", nil)
  -- find_definition uses cwd/buf; set by passing a buffer name
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/src/main.s")
  def = docs.find_definition("delay", buf)
  ok(def ~= nil, "definition found")
  eq(def.lnum, 2)
  eq(#def.comments, 1)
  eq(def.comments[1], "# void delay(int cycles)")
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

test("find_definition finds c function with comments", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({
    "// Adds two numbers",
    "// int add(int a, int b)",
    "int add(int a, int b) {",
    "  return a + b;",
    "}",
  }, tmp .. "/src/test.c")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/src/main.s")
  local def = docs.find_definition("add", buf)
  ok(def ~= nil, "definition found")
  eq(def.lnum, 3)
  ok(#def.comments >= 2, "comments found")
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

test("hover returns definition line even without comments", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "foo:", "  ret" }, tmp .. "/src/foo.s")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/src/main.s")
  local h = docs.hover("foo", buf)
  ok(h ~= nil, "hover found")
  ok(h:find("foo:", 1, true) ~= nil, "hover mentions definition")
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

test("hover returns comments text", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/src", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "# //.func (int a, int b)", "bar:", "  ret" }, tmp .. "/src/bar.s")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/src/main.s")
  local h = docs.hover("bar", buf)
  ok(h ~= nil, "hover found")
  ok(h:find("# //%.func %(int a, int b%)", 1) ~= nil or h:find("func", 1, true) ~= nil, "hover mentions func")
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

print(string.format("\n%d/%d passed", test_count - fail_count, test_count))
if fail_count > 0 then vim.cmd("cquit 1") end