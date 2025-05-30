-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>qs", function()
  require("persistence").load()
end, { desc = "Load session for current dir" })

vim.keymap.set("n", "<leader>qS", function()
  require("persistence").select()
end, { desc = "Select session to load" })

vim.keymap.set("n", "<leader>ql", function()
  require("persistence").load({ last = true })
end, { desc = "Load last session" })

vim.keymap.set("n", "<leader>qd", function()
  require("persistence").stop()
end, { desc = "Stop persistence (disable autosave)" })

require("config.ComplexKeymaps.comment-on-f2")

vim.keymap.set("n", "<leader>kl", function()
  vim.lsp.buf.format({ async = true })
  vim.notify("Formatted", vim.log.levels.INFO)
end, { desc = "Format code" })

require("config.ComplexKeymaps.close-others")

-- Normal mode: select all
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select All (Normal)" })

-- Insert mode: escape to normal, select all
vim.keymap.set("i", "<C-a>", "<Esc>ggVG", { desc = "Select All (Insert)" })

-- Visual mode: reselect entire buffer (just make sure entire buffer is selected)
vim.keymap.set("v", "<C-a>", "<Esc>ggVG", { desc = "Select All (Visual)" })

vim.keymap.set("n", "<F11>", function()
  vim.lsp.buf.code_action()
end, { desc = "Quick fix", noremap = true, silent = true })

vim.keymap.set("n", "<C-r><C-r>", function()
  vim.lsp.buf.rename()
end, { desc = "Rename", noremap = true, silent = true })

require("config.ComplexKeymaps.dotnet-build")
