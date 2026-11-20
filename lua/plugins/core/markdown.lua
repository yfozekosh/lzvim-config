-- Markdown: no markdownlint.
--
-- LazyVim's lang.markdown extra lints every .md file with markdownlint-cli2,
-- which floods the buffer with style warnings (80-column line length, table
-- pipe alignment, blank lines around lists...). The marksman LSP still
-- provides links/headings/go-to-definition, and prettier still formats.
-- markdownlint-cli2 is also dropped as a formatter (LazyVim only ran it when
-- markdownlint diagnostics existed) and from Mason, so it gets uninstalled.
-- prettier is de-duplicated (the markdown and prettier extras both add it).
local function without(list, name)
  return vim.tbl_filter(function(x)
    return x ~= name
  end, list or {})
end

return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      for _, ft in ipairs({ "markdown", "markdown.mdx" }) do
        opts.linters_by_ft[ft] = without(opts.linters_by_ft[ft], "markdownlint-cli2")
      end
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      for _, ft in ipairs({ "markdown", "markdown.mdx" }) do
        if opts.formatters_by_ft[ft] then
          -- The markdown and prettier extras both add prettier; run it once.
          opts.formatters_by_ft[ft] = vim.list.unique(without(opts.formatters_by_ft[ft], "markdownlint-cli2"))
        end
      end
    end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = without(opts.ensure_installed, "markdownlint-cli2")
    end,
  },
}
