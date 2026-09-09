-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.root_spec = { "cwd" }
vim.g.autoformat = false
vim.g.lazyvim_disable_animations = true

-- WSL clipboard bridge: use win32yank.exe (installed by setup.sh's
-- install_win32yank migration) so nvim yank/paste share the real Windows
-- clipboard with Alacritty and tmux. Only applies under WSL and only if the
-- binary is actually on PATH, so this is a no-op elsewhere.
if vim.fn.has("wsl") == 1 and vim.fn.executable("win32yank.exe") == 1 then
  vim.g.clipboard = {
    name = "win32yank",
    copy = {
      ["+"] = "win32yank.exe -i --crlf",
      ["*"] = "win32yank.exe -i --crlf",
    },
    paste = {
      ["+"] = "win32yank.exe -o --lf",
      ["*"] = "win32yank.exe -o --lf",
    },
    cache_enabled = true,
  }
end
vim.opt.clipboard = "unnamedplus"

vim.lsp.config("roslyn", {
  on_attach = function()
    -- nop.
  end,
  settings = {
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
    ["csharp|code_lens"] = {
      dotnet_enable_references_code_lens = true,
    },
    ["csharp|completion"] = {
      ["dotnet_provide_regex_completions"] = true,
      ["dotnet_show_completion_items_from_unimported_namespaces"] = true,
    },
    ["csharp|background_analysis"] = {
      ["dotnet_analyzer_diagnostics_scope"] = "fullSolution",
      ["dotnet_compiler_diagnostics_scope"] = "fullSolution",
    },
  },
})

