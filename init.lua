-- if raspberry PI - run minimal config:
if vim.osname == "Linux" and vim.fn.filereadable("/etc/rpi-issue") == 1 then
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
        { out, "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end
  vim.opt.rtp:prepend(lazypath)

  -- set number and relativenumber
  vim.o.number = true
  vim.o.relativenumber = true
  return
end

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Set root dir as the one that nvim was opened in.
local util = require("lazyvim.util")

local root = util.root.get()
vim.notify("Root: " .. root)
