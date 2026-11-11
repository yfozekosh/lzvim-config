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

local profile = require("config.profile")

local spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
}

-- LazyVim extras must be imported before the user's own plugin modules, so
-- user specs can override extra defaults.
if profile.has("git") then
  table.insert(spec, { import = "lazyvim.plugins.extras.lang.git" })
end
if profile.has("embedded") then
  table.insert(spec, { import = "lazyvim.plugins.extras.lang.clangd" })
end
if profile.has("ai") then
  table.insert(spec, { import = "lazyvim.plugins.extras.ai.copilot-chat" })
end
if profile.has("frontend") then
  table.insert(spec, { import = "lazyvim.plugins.extras.lang.typescript" })
  table.insert(spec, { import = "lazyvim.plugins.extras.lang.angular" })
  table.insert(spec, { import = "lazyvim.plugins.extras.formatting.prettier" })
end

-- Feature-owned plugin modules.
table.insert(spec, { import = "plugins.core" })
if profile.has("ai") then
  table.insert(spec, { import = "plugins.ai" })
end
if profile.has("dotnet") then
  table.insert(spec, { import = "plugins.dotnet" })
end
if profile.has("embedded") then
  table.insert(spec, { import = "plugins.embedded" })
end

require("lazy").setup({
  spec = spec,
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

require("config.colors")
