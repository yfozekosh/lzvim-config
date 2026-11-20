-- Spinner in the statusline while a user-initiated LSP request (gr, gd, gI,
-- hover, rename...) is slow to answer. See lua/config/lsp_pending.lua.
return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    local pending = require("config.lsp_pending")
    pending.setup()
    opts.sections = opts.sections or {}
    opts.sections.lualine_x = opts.sections.lualine_x or {}
    table.insert(opts.sections.lualine_x, 1, {
      pending.status,
      cond = function()
        return pending.status() ~= ""
      end,
      color = "DiagnosticWarn",
    })
  end,
}
