local M = {}

function M.enabled()
  local override = vim.env.YF_NVIM_MINIMAL
  if override == "1" then
    return true
  end
  if override == "0" then
    return false
  end
  return vim.fn.filereadable("/etc/rpi-issue") == 1
end

local function try_set(name, value)
  pcall(function()
    vim.opt[name] = value
  end)
end

function M.setup()
  vim.g.mapleader = " "
  vim.g.maplocalleader = "\\"
  vim.g.autoformat = false
  vim.g.snacks_animate = false
  vim.opt.shadafile = "NONE"
  vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
  vim.opt.autowrite = true
  vim.opt.completeopt = "menu,menuone,noselect"
  vim.opt.confirm = true
  vim.opt.cursorline = true
  vim.opt.expandtab = true
  vim.opt.fillchars = { eob = " ", fold = " ", foldopen = "+", foldclose = "-", foldsep = " ", diff = "/" }
  vim.opt.foldlevel = 99
  vim.opt.foldmethod = "indent"
  vim.opt.foldtext = ""
  vim.opt.formatoptions = "jcroqlnt"
  vim.opt.grepformat = "%f:%l:%c:%m,%f:%l:%m"
  vim.opt.grepprg = vim.fn.executable("rg") == 1 and "rg --vimgrep --no-heading" or "grep -Rn"
  vim.opt.ignorecase = true
  vim.opt.inccommand = "nosplit"
  vim.opt.laststatus = 3
  vim.opt.linebreak = true
  vim.opt.list = true
  vim.opt.mouse = "a"
  vim.opt.number = true
  vim.opt.pumblend = 10
  vim.opt.pumheight = 10
  vim.opt.relativenumber = true
  vim.opt.ruler = false
  vim.opt.scrolloff = 4
  vim.opt.shiftround = true
  vim.opt.shiftwidth = 2
  vim.opt.showmode = false
  vim.opt.sidescrolloff = 8
  vim.opt.signcolumn = "yes"
  vim.opt.smartcase = true
  vim.opt.smartindent = true
  vim.opt.spelllang = "en"
  vim.opt.splitbelow = true
  vim.opt.splitkeep = "screen"
  vim.opt.splitright = true
  vim.opt.tabstop = 2
  vim.opt.termguicolors = true
  vim.opt.timeoutlen = 300
  vim.opt.undofile = true
  vim.opt.undolevels = 10000
  vim.opt.updatetime = 200
  vim.opt.virtualedit = "block"
  vim.opt.wildmode = "longest:full,full"
  vim.opt.wrap = false
  vim.opt.shortmess:append("WIcC")
  try_set("jumpoptions", "view")
  try_set("smoothscroll", true)
  try_set("winminwidth", 5)

  require("config.minimal.colors").setup()
  require("config.minimal.statusline").setup()
  require("config.minimal.pickers").setup()
  require("config.minimal.keymaps").setup()
end

return M
