local comment = require("Comment.api")

local function toggle_comment_and_move_next()
  local mode = vim.fn.mode()

  if mode == "n" then
    -- normal mode: toggle current line comment
    comment.toggle.linewise.current()
    vim.cmd("normal! j")
  elseif mode == "v" or mode == "V" or mode == "\22" then
    -- visual modes: toggle comment on selection
    -- Use esc to exit visual temporarily
    vim.cmd("normal! <Esc>")
    comment.toggle.linewise(vim.fn.visualmode())
    vim.cmd("normal! j")
    -- Re-enter visual mode (same range not restored perfectly, but close)
    -- You can skip restoring visual selection if too complex
  elseif mode == "i" then
    -- insert mode: exit insert, toggle current line, move down, then return to insert
    vim.cmd("stopinsert")
    comment.toggle.linewise.current()
    vim.cmd("normal! j")
    vim.cmd("startinsert")
  else
    -- fallback: treat as normal mode
    comment.toggle.linewise.current()
    vim.cmd("normal! j")
  end
end

vim.keymap.set(
  { "n", "v", "i" },
  "<F2>",
  toggle_comment_and_move_next,
  { desc = "Toggle comment and move down, restore mode" }
)
