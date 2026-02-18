if vim.g.loaded_dotbee == 1 then
  return
end
vim.g.loaded_dotbee = 1

local COMMAND_NAME = "Dotbee"

vim.api.nvim_create_user_command(COMMAND_NAME, function(opts)
    require("dotbee").ui.toggle()
end, {
  nargs = "*",
})

vim.keymap.set("n", "<leader>DD", function()
  vim.cmd("Lazy reload dotbee.nvim")
  vim.cmd(COMMAND_NAME)
end, { desc = "Reload Dotbee UI" })

vim.keymap.set("n", "<leader>dd", function()
  vim.cmd(COMMAND_NAME)
end, { desc = "Toggle Dotbee UI" })
