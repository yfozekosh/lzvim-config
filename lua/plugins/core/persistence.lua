-- ~/.config/nvim/lua/plugins/persistence.lua
return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {
    dir = vim.fn.expand(vim.fn.stdpath("state") .. "/sessions"),
    autosave = true, -- auto save session on exit
    autoload = true, -- auto load session when entering dir
    follow_cwd = true, -- track current working directory
  },
}
