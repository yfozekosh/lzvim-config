local M = {}

local modes = {
  n = "NORMAL",
  i = "INSERT",
  v = "VISUAL",
  V = "V-LINE",
  ["\22"] = "V-BLOCK",
  c = "COMMAND",
  t = "TERM",
  R = "REPLACE",
}

local function lsp_count()
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = 0 })
  if not ok then
    ok, clients = pcall(vim.lsp.buf_get_clients, 0)
  end
  if ok and type(clients) == "table" then
    return #clients
  end
  return 0
end

function M.render()
  local mode = vim.api.nvim_get_mode().mode
  local mode_name = modes[mode] or modes[mode:sub(1, 1)] or mode:upper()

  local parts = {}
  parts[#parts + 1] = "%#StatusLineMode# " .. mode_name .. " %#StatusLine#"

  local name = vim.fn.expand("%:t")
  if name == "" then
    name = "[No Name]"
  end
  parts[#parts + 1] = " " .. name
  if vim.bo.modified then
    parts[#parts + 1] = "[+]"
  end
  if vim.bo.readonly then
    parts[#parts + 1] = "[ro]"
  end

  local counts = { 0, 0, 0, 0 }
  for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
    local severity = diagnostic.severity
    if severity and counts[severity] then
      counts[severity] = counts[severity] + 1
    end
  end
  local labels = {
    { "DiagnosticError", "E", counts[vim.diagnostic.severity.ERROR] },
    { "DiagnosticWarn", "W", counts[vim.diagnostic.severity.WARN] },
    { "DiagnosticInfo", "I", counts[vim.diagnostic.severity.INFO] },
    { "DiagnosticHint", "H", counts[vim.diagnostic.severity.HINT] },
  }
  for _, entry in ipairs(labels) do
    if entry[3] > 0 then
      parts[#parts + 1] = "%#" .. entry[1] .. "#" .. entry[2] .. entry[3]
    end
  end

  local clients = lsp_count()
  if clients > 0 then
    parts[#parts + 1] = " lsp:" .. clients
  end

  if vim.bo.filetype ~= "" then
    parts[#parts + 1] = " " .. vim.bo.filetype
  end

  parts[#parts + 1] = "%="
  parts[#parts + 1] = vim.fn.line(".") .. ":" .. vim.fn.col(".")

  return table.concat(parts)
end

function M.setup()
  _G.__yf_minimal_statusline = M.render
  vim.o.statusline = "%!v:lua.__yf_minimal_statusline()"
end

return M
