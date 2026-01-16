--
-- every spec file under the "plugins" directory will be loaded automatically by lazy.nvim
-- In your plugin files, you can:
-- * add extra plugins
-- * disable/enabled LazyVim plugins
-- * override the configuration of LazyVim plugins

return {
  -- add gruvbox
  -- { "ellisonleao/gruvbox.nvim" },
  { "nvim-mini/mini.animate", enabled = false },
  { "Mofiqul/vscode.nvim", enabled = true },
  { "johngrib/vim-game-snake" },

  -- Configure LazyVim to load gruvbox
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vscode",
      opts = {
        root = {
          autochdir = false,
          patters = {},
        },
      },
    },
  },
  {
    "numToStr/Comment.nvim",
    opts = {
      -- add any options here
    },
  },
}
