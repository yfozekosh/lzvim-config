-- GNU RISC-V assembly comments start with `#`.  Neovim's default asm
-- ftplugin uses `;` (a statement separator on RISC-V), so override it here.
vim.bo.commentstring = "# %s"

-- The Tree-sitter asm parser handles most highlighting well but does not
-- always capture `#` comments in directive-heavy files.  Keep Treesitter for
-- the rich instruction/directive colors and overlay comments with a
-- buffer-local extmark highlighter.
local buf = vim.api.nvim_get_current_buf()
if vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "asm" then
  local ns = vim.api.nvim_create_namespace("asm_comments")
  local group = vim.api.nvim_create_augroup("AsmComments" .. buf, { clear = true })

  local function highlight_comments()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      local start = line:find("#", 1, true)
      if start then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, start - 1, {
          end_col = #line,
          hl_group = "Comment",
          priority = 200,
        })
      end
    end
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = highlight_comments,
  })
  highlight_comments()
end
