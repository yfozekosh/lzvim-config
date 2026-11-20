-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.root_spec = { "cwd" }
vim.g.autoformat = false
vim.g.snacks_animate = false

-- Don't persist state between sessions (command/search history, registers,
-- marks, jumplist). Skips the ShaDa read at startup.
vim.opt.shadafile = "NONE"

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

-- Debug-level LSP logging with cheap summaries + ms timestamps, on tmpfs.
-- See lua/config/lsp_log.lua.
require("config.lsp_log").setup()

-- Record main-loop freezes (>250ms) to $XDG_RUNTIME_DIR/nvim/stalls.log.
-- See lua/config/stall_log.lua.
require("config.stall_log").setup()

if require("config.profile").has("dotnet") then
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
    -- Only takes effect if LazyVim's `codelens.enabled` is turned on (it is
    -- off by default), so this costs nothing as-is.
    ["csharp|code_lens"] = {
      dotnet_enable_references_code_lens = true,
    },
    ["csharp|completion"] = {
      ["dotnet_provide_regex_completions"] = true,
      ["dotnet_show_completion_items_from_unimported_namespaces"] = true,
    },
    -- Analyzers over the full solution are the expensive part and starve
    -- interactive requests (gd/gI/hover), so they only run on open files.
    -- Compiler diagnostics stay solution-wide: much cheaper, and they keep
    -- every project's compilation warm, so the first `gr` (find references)
    -- after startup doesn't have to build all of them on demand (~5s cold).
    ["csharp|background_analysis"] = {
      ["dotnet_analyzer_diagnostics_scope"] = "openFiles",
      ["dotnet_compiler_diagnostics_scope"] = "fullSolution",
    },
  },
})
end
