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

print("minimal tests OK")
