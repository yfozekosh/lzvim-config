-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local function reload_lsp_and_treesitter()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      -- Get clients attached to this buffer using new API
      local clients = vim.lsp.get_clients({ bufnr = buf })

      for _, client in pairs(clients) do
        if client.supports_method and client.supports_method("textDocument/didClose") then
          client.notify("textDocument/didClose", { textDocument = { uri = vim.uri_from_bufnr(buf) } })
          client.notify("textDocument/didOpen", { textDocument = vim.lsp.util.make_text_document_params(buf) })
        end
      end

      -- Reload Treesitter parser for this buffer
      local ts = require("nvim-treesitter.parsers")
      local parser = ts.get_parser(buf)
      if parser then
        parser:reload()
      end
    end
  end

  vim.notify("LSP and Treesitter reloaded after session restore", vim.log.levels.INFO, { title = "Persistence" })
end

vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = reload_lsp_and_treesitter,
})
