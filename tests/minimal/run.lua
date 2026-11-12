-- Run from the repo root:
--   nvim --headless -u NONE -l tests/minimal/run.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local minimal = require("config.minimal")

-- Detection: environment override wins over the hardware marker.
vim.env.YF_NVIM_MINIMAL = "1"
assert(minimal.enabled(), "YF_NVIM_MINIMAL=1 must force the minimal config")
vim.env.YF_NVIM_MINIMAL = "0"
assert(not minimal.enabled(), "YF_NVIM_MINIMAL=0 must disable it")
vim.env.YF_NVIM_MINIMAL = nil

minimal.setup()

assert(vim.g.mapleader == " ", "leader must be space")
assert(vim.o.number and vim.o.relativenumber, "line numbers must be on")
assert(vim.o.signcolumn == "yes", "sign column must always be visible")
assert(vim.o.expandtab and vim.o.shiftwidth == 2 and vim.o.tabstop == 2, "2-space indent")
assert(vim.o.termguicolors, "true color must be on")
assert(vim.o.laststatus == 3 and vim.o.showmode == false, "global statusline")
assert(vim.o.shadafile == "NONE", "shada must be disabled")
assert(vim.fn.exists(":Lazy") == 0, "the minimal config must not define :Lazy")

local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end

assert(hl("Normal").fg == tonumber("D8DEE9", 16), "Nord foreground")
assert(hl("Normal").bg == tonumber("2E3440", 16), "Nord background")
assert(hl("Comment").fg == tonumber("616E88", 16), "Nord comment")
assert(hl("Visual").bg == tonumber("434C5E", 16), "Nord selection")
assert(hl("DiagnosticError").fg == tonumber("BF616A", 16), "Nord error")

local statusline = require("config.minimal.statusline")
assert(vim.o.statusline:find("__yf_minimal_statusline", 1, true), "statusline wired")
local line = statusline.render()
assert(type(line) == "string" and #line > 0, "render returns text")
assert(line:find("[No Name]", 1, true), "unnamed buffer label")
local columns = statusline.render()
assert(columns:find("%d+:%d+") ~= nil, "line:column position")

local pickers = require("config.minimal.pickers")
local repo = vim.fn.getcwd()
local dir = repo .. "/.tmp/minimal-pickers"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/.git", "p")
vim.fn.writefile({ "x" }, dir .. "/a.lua")
vim.fn.writefile({ "x" }, dir .. "/.git/config")
vim.fn.chdir(dir)
local files = pickers.list_files()
assert(vim.tbl_contains(files, "a.lua"), "lists regular files")
for _, file in ipairs(files) do
  assert(not file:find("/.git/", 1, true) and not file:match("^%.git/"), ".git must be excluded")
end
vim.fn.mkdir(dir .. "/empty", "p")
vim.fn.chdir(dir .. "/empty")
assert(#pickers.list_files() == 0, "empty directory returns no files")
vim.fn.chdir(repo)
assert(pickers.grep_command("a b'c") == "grep! " .. vim.fn.shellescape("a b'c"), "grep is shell-escaped")
assert(vim.fn.maparg("<leader><space>", "n") ~= "", "find-files map")
assert(vim.fn.maparg("<leader>/", "n") ~= "", "grep map")
assert(vim.fn.maparg("<leader>e", "n") ~= "", "explorer map")
vim.fn.delete(dir, "rf")

local keymaps = require("config.minimal.keymaps")
for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>", "<S-h>", "<S-l>", "[b", "]b", "<C-s>", "<C-a>", "<F2>", "<F11>", "<F12>", "<leader>cb", "<leader>cc", "<leader>fw", "[d", "]d", "[q", "]q" }) do
  assert(vim.fn.maparg(lhs, "n") ~= "", "missing mapping " .. lhs)
end
assert(vim.fn.maparg("<leader>bb", "n") ~= "", "alternate buffer map")

vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
vim.bo.commentstring = "-- %s"
vim.bo.filetype = "lua"
keymaps.toggle_comment_and_next()
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "-- foo", "F2 comments")
assert(pcall(vim.cmd, "normal [d"), "diagnostic jump must not error")
assert(pcall(keymaps.code_action), "F11 must not error without LSP")
vim.cmd("enew")
vim.cmd("enew")
keymaps.close_others()
assert(#vim.fn.getbufinfo({ buflisted = 1 }) == 1, "F12 keeps one buffer")

-- Review fix: statusline must escape percent signs in filenames.
do
  local statusline = require("config.minimal.statusline")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, "100%#ErrorMsg#name.txt")
  local rendered = statusline.render()
  assert(rendered:find("100%%#ErrorMsg#name.txt", 1, true), "statusline escapes percent in filename")
  local evaluated = vim.api.nvim_eval_statusline(rendered, {})
  assert(evaluated.str:find("100%#ErrorMsg#name.txt", 1, true), "statusline renders literal filename")
  vim.cmd("enew")
  vim.cmd("bwipeout! " .. buf)
end

-- Review fix: `grep -Rn` output must parse into usable quickfix entries.
do
  local old_grepprg = vim.o.grepprg
  vim.o.grepprg = "grep -Rn"
  vim.cmd("silent! grep! " .. vim.fn.shellescape("Nord-like colorscheme"))
  local valid = false
  for _, item in ipairs(vim.fn.getqflist()) do
    if item.lnum > 0 and item.bufnr > 0 then
      valid = true
    end
  end
  assert(valid, "grep fallback produces valid quickfix entries")
  vim.cmd("cclose")
  vim.o.grepprg = old_grepprg
end

-- Review fix: Ex-special characters in grep patterns are escaped.
assert(
  pickers.grep_command("%") == "grep! " .. vim.fn.shellescape("%", 1),
  "grep escapes Ex-special characters"
)

-- Review fix: close_others must preserve terminals and unlisted explorers.
do
  vim.cmd("enew")
  local current = vim.api.nvim_get_current_buf()
  vim.bo[current].buflisted = false
  vim.bo[current].filetype = "netrw"
  keymaps.close_others()
  assert(vim.bo[current].buflisted == false, "close_others keeps explorer unlisted")
end
do
  vim.cmd("enew")
  vim.cmd("terminal")
  local term = vim.api.nvim_get_current_buf()
  assert(vim.bo[term].buftype == "terminal", "terminal buffer created")
  vim.cmd("enew")
  local current = vim.api.nvim_get_current_buf()
  assert(current ~= term, "new buffer is not the terminal")
  keymaps.close_others()
  assert(
    vim.api.nvim_buf_is_valid(term) and vim.bo[term].buftype == "terminal",
    "close_others keeps terminals"
  )
  vim.cmd("bd! " .. term)
end

print("minimal tests OK")
