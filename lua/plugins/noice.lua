return {
  "folke/noice.nvim",
  opts = function(_, opts)
    opts.views = opts.views or {}
    opts.views.hover = vim.tbl_deep_extend("force", opts.views.hover or {}, {
      border = { style = "rounded" },
    })
    opts.views.signature = vim.tbl_deep_extend("force", opts.views.signature or {}, {
      border = { style = "rounded" },
    })
  end,
}
