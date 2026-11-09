--- Project-wide completion for assembly macros (`.macro`).
local M = {}

local source = {}

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

function source:enabled()
  return vim.bo.filetype == "asm"
end

function source:get_completions(ctx, callback)
  local empty = { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  local bufnr = (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local start = name ~= "" and name or vim.fn.getcwd()

  local ok, asm_docs = pcall(require, "asm_docs")
  if not ok or not asm_docs then
    callback(empty)
    return
  end

  local items = {}
  local seen = {}
  for _, macro in ipairs(asm_docs.list_macros(start)) do
    if not seen[macro.name] then
      seen[macro.name] = true
      local doc = macro.name
      if macro.comments and #macro.comments > 0 then
        doc = doc .. "\n\n" .. table.concat(macro.comments, "\n")
      end
      doc = doc .. "\n\n```asm\n" .. macro.defline .. "\n```"
      doc = doc .. "\n\n_" .. macro.path .. ":" .. macro.lnum .. "_"
      items[#items + 1] = {
        label = macro.name,
        filterText = macro.name,
        kind = vim.lsp.protocol.CompletionItemKind.Snippet,
        detail = "macro",
        documentation = { kind = "markdown", value = doc },
        insertText = macro.name,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
      }
    end
  end

  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

function M.new(opts)
  return source.new(opts)
end

return M