vim.keymap.set("n", "<F12>", function()
  local current = vim.api.nvim_get_current_buf()
  local closed_count = 0

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_ft = vim.bo[buf].filetype
    local is_current = buf == current
    local is_terminal = buf_ft == "terminal"
    local is_explorer = buf_ft == "neo-tree" or buf_ft == "NvimTree"

    if vim.bo[buf].buflisted and not is_current and not is_terminal and not is_explorer then
      vim.cmd("bd! " .. buf)
      closed_count = closed_count + 1
    end
  end

  vim.bo[current].buflisted = true
  vim.cmd("buffer " .. current)

  vim.opt.number = true
  vim.opt.relativenumber = true
  vim.cmd("redrawstatus")
  vim.cmd("redraw")

  local name = vim.fn.expand("%:t")
  if name == "" then
    name = "[No Name]"
  end
  vim.notify(
    "Closed " .. closed_count .. " buffer(s). Still viewing: " .. name,
    vim.log.levels.INFO,
    { title = "LazyVim" }
  )
end, { desc = "Close other file buffers (keep terminals & explorers)" })
