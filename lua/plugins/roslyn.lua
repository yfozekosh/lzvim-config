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
    config = {
      -- Example: enable code lens, inlay hints, etc.
      settings = {
        ["csharp|code_lens"] = {
          dotnet_enable_references_code_lens = true,
        },
        ["csharp|inlay_hints"] = {
          csharp_enable_inlay_hints_for_implicit_object_creation = true,
          csharp_enable_inlay_hints_for_implicit_variable_types = true,
          csharp_enable_inlay_hints_for_lambda_parameter_types = true,
          csharp_enable_inlay_hints_for_types = true,
          dotnet_enable_inlay_hints_for_indexer_parameters = true,
          dotnet_enable_inlay_hints_for_literal_parameters = true,
          dotnet_enable_inlay_hints_for_object_creation_parameters = true,
          dotnet_enable_inlay_hints_for_other_parameters = true,
          dotnet_enable_inlay_hints_for_parameters = true,
          dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
          dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
          dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
        },
      },
    },
  },
}
