local util = require("lspconfig.util")

return {
  "seblyng/roslyn.nvim",
  ft = "cs",
  opts = {
    -- NOTE: Configure the server cmd if you didn't install via Mason:
    -- config = {
    --   cmd = {
    --     "dotnet",
    --     "/path/to/Microsoft.CodeAnalysis.LanguageServer.dll",
    --     "--stdio",
    --   },
    -- },

    -- Override root_dir to locate closest directory with .sln
    root_dir = function(fname)
      return util.search_ancestors(fname, function(dir)
        if #vim.fn.glob(vim.fs.joinpath(dir, "*.sln")) > 0 then
          return dir
        end
      end)
    end,

    -- You can tweak roslyn.nvim-specific opts here:
    filewatching = "auto", -- default
    -- optionally, implement choose_target, ignore_target, lock_target, broad_search, etc.

    -- Pass through any `vim.lsp.start` config here:
  },
}
