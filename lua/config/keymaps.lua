-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

require("config.ComplexKeymaps.comment-on-f2")

require("config.ComplexKeymaps.close-others")

-- Normal mode: select all
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select All (Normal)" })

-- Insert mode: escape to normal, select all
vim.keymap.set("i", "<C-a>", "<Esc>ggVG", { desc = "Select All (Insert)" })

-- Accept Copilot inline suggestion with Tab in insert mode
if require("config.profile").has("ai") then
  vim.keymap.set("i", "<Tab>", function()
    return require("copilot.suggestion").accept() or "\t"
  end, { expr = true, desc = "Accept Copilot suggestion" })
end

-- Visual mode: reselect entire buffer (just make sure entire buffer is selected)
vim.keymap.set("v", "<C-a>", "<Esc>ggVG", { desc = "Select All (Visual)" })

vim.keymap.set("n", "<F11>", function()
  vim.lsp.buf.code_action()
end, { desc = "Quick fix", noremap = true, silent = true })

if require("config.profile").has("dotnet") then
  require("config.ComplexKeymaps.dotnet-build")
  require("config.ComplexKeymaps.dotnet-format")
end
require("config.ComplexKeymaps.build")

vim.keymap.set("n", "<leader>cb", function()
  require("config.ComplexKeymaps.build").run()
end, { desc = "Build (make)", noremap = true, silent = true })

vim.keymap.set("n", "<leader>cc", function()
  require("config.ComplexKeymaps.build").run("clean")
end, { desc = "Clean (make clean)", noremap = true, silent = true })

vim.keymap.set("n", "<leader>fw", function()
  vim.notify(vim.fn.expand("%:p"))
end, { desc = "Show file path", noremap = true })

vim.api.nvim_create_user_command("PwdFile", function()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  vim.notify(dir, vim.log.levels.INFO, { title = "File directory (pwd)" })
end, { desc = "Show the directory (pwd) of the current file" })
