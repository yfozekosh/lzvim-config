local util = require("dotbee.util")

local M = {}
local m = {
  on_enter = function()
    vim.notify("Enter pressed in float buffer")
  end,
}

local state = {
  win = nil,
  buf = nil,
}

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function open_float()
  -- Create scratch buffer
  local buf

  if not is_valid_buf(state.buf) then
    buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
    state.buf = buf
    -- Scratch / UI-ish options
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true
  else
    buf = state.buf
  end

  local width = util.width(80)
  local height = util.height(80)

  -- Center
  local col = math.floor((vim.o.columns - width) / 2)
  -- Subtract cmdheight-like area a bit; keep it safe:
  local row = math.floor((vim.o.lines - height) / 2) - 1
  if row < 0 then
    row = 0
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    border = "rounded",
  })
  state.win = win

  -- Close mappings (buffer-local)
  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "q", M.toggle, opts)
  vim.keymap.set("n", "<Esc>", M.toggle, opts)
  vim.keymap.set("n", "<CR>", m.on_enter, opts)

  -- Example placeholder text
  if not state.isCreated and buf ~= nil then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Scratch UI buffer",
      "",
      "- type anything",
      "- press q or <Esc> to close",
    })
    state.isCreated = true
  end
end

function M.toggle()
  if is_valid_win(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  else
    open_float()
  end
end

function M.add_on_enter(fn)
  m.on_enter = fn
end

return M
