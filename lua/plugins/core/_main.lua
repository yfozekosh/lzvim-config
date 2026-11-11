-- Core plugin specs. Loaded unconditionally by config/lazy.lua.

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
  -- uses Comment.api for the <F2> mapping. Loaded on first <F2> press.
  {
    "numToStr/Comment.nvim",
    lazy = true,
  },
}
