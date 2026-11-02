-- Colour overrides that have to be applied after the colorscheme is set.

-- Lazy entry point for the extmark inspector; the 200-line implementation
-- only loads when you actually use it.
vim.api.nvim_create_user_command("InspectExtmarks", function(cmd)
  require("config.extmarks").inspect({ scope = (cmd.args ~= "" and cmd.args) or "line" })
end, { nargs = "?" })

vim.keymap.set("n", "<leader>ue", function()
  require("config.extmarks").inspect({ scope = "line" })
end, { desc = "Inspect extmarks (line)" })

vim.api.nvim_set_hl(0, "SnacksPickerDir", { link = "Directory" })
vim.api.nvim_set_hl(0, "SnacksPickerPathHidden", { link = "NonText" })
vim.api.nvim_set_hl(0, "SnacksPickerGitStatusUntracked", { link = "DiagnosticInfo" })

-- Inlay hints: avoid "Special" (often looks white in Nord).
vim.api.nvim_set_hl(0, "MyInlayHint", { fg = "#566C8A", italic = true })
vim.api.nvim_set_hl(0, "LspInlayHint", { link = "MyInlayHint" })
