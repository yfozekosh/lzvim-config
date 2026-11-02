--
-- every spec file under the "plugins" directory will be loaded automatically by lazy.nvim
-- In your plugin files, you can:
-- * add extra plugins
-- * disable/enabled LazyVim plugins
-- * override the configuration of LazyVim plugins

return {
  { "shaunsingh/nord.nvim" },

  -- Colorscheme. Root behaviour is set via vim.g.root_spec in config/options.lua.
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "nord",
    },
  },

  -- Not bundled with LazyVim 16, but config/ComplexKeymaps/comment-on-f2.lua
  -- uses Comment.api for the <F2> mapping.
  {
    "numToStr/Comment.nvim",
  },
}
