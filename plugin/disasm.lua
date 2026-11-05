require("disasm").setup(vim.g.disasm or {})

vim.api.nvim_create_user_command("DisasmOpen", function(opts)
  require("disasm").open(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", complete = "file", desc = "Open disassembly split" })

vim.api.nvim_create_user_command("DisasmClose", function()
  require("disasm").close()
end, { desc = "Close disassembly split" })

vim.api.nvim_create_user_command("DisasmToggle", function(opts)
  require("disasm").toggle(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", complete = "file", desc = "Toggle disassembly split" })

vim.api.nvim_create_user_command("DisasmRefresh", function()
  require("disasm").refresh()
end, { desc = "Refresh disassembly" })
