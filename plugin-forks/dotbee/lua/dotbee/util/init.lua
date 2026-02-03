local M = {}

function M.width(percent)
  local columns = vim.o.columns
  return math.floor(columns * (percent / 100))
end

function M.height(percent)
  local lines = vim.o.lines
  return math.floor(lines * (percent / 100))
end

return M
