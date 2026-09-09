local util = require("lspconfig.util")

return {
  "seblyng/roslyn.nvim",
  ft = { "cs", "razor" },
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
    -- root_dir = function(fnamec>
    --   return util.search_ancestors(fname, function(dir)
    --     if #vim.fn.glob(vim.fs.joinpath(dir, "*.sln")) > 0 then
    --       return dir
    --     end
    --   end)
    -- end,

    -- You can tweak roslyn.nvim-specific opts here:
    filewatching = "auto", -- default
    -- optionally, implement choose_target, ignore_target, lock_target, broad_search, etc.

    -- Pass through any `vim.lsp.start` config here:
  },
  lazy = false,
  -- Auto-install the Roslyn language server via Mason (Crashdummyy registry)
  -- on first load, so a fresh machine doesn't need a manual :MasonInstall.
  config = function(_, opts)
    local ok, registry = pcall(require, "mason-registry")
    if ok then
      registry.refresh(function()
        if registry.has_package("roslyn") then
          local pkg = registry.get_package("roslyn")
          if not pkg:is_installed() then
            vim.notify("Installing Roslyn language server via Mason...", vim.log.levels.INFO)
            pkg:install()
          end
        end
      end)
    end
    require("roslyn").setup(opts)
  end,
}
