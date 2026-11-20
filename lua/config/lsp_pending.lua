-- Statusline indicator for slow, user-initiated LSP requests.
--
-- `gr`/`gd`/`gI` etc. go through Snacks pickers, which only open once the
-- server answers, so a slow server (e.g. Roslyn's cold find-references) looks
-- like nvim froze. This tracks pending requests via the `LspRequest` autocmd
-- and, once one has been waiting longer than DELAY_MS, shows a spinner with
-- the method name and elapsed time in lualine (see
-- lua/plugins/core/lsp-pending.lua). Background requests (highlights, inlay
-- hints, semantic tokens, completion...) are ignored.
local M = {}

local DELAY_MS = 300
local FRAME_MS = 100
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Requests that are only sent because the user asked for something.
local TRACKED = {
  ["textDocument/definition"] = "definition",
  ["textDocument/declaration"] = "declaration",
  ["textDocument/typeDefinition"] = "type definition",
  ["textDocument/implementation"] = "implementations",
  ["textDocument/references"] = "references",
  ["textDocument/hover"] = "hover",
  ["textDocument/rename"] = "rename",
  ["textDocument/prepareRename"] = "rename",
  ["textDocument/codeAction"] = "code actions",
  ["textDocument/formatting"] = "format",
  ["textDocument/rangeFormatting"] = "format",
  ["textDocument/documentSymbol"] = "symbols",
  ["workspace/symbol"] = "workspace symbols",
  ["callHierarchy/incomingCalls"] = "incoming calls",
  ["callHierarchy/outgoingCalls"] = "outgoing calls",
  ["textDocument/prepareCallHierarchy"] = "call hierarchy",
}

---@type table<string, { label: string, client: string, start: integer }>
local pending = {}
local timer ---@type uv.uv_timer_t?
local frame = 0

local function count()
  return vim.tbl_count(pending)
end

local function refresh()
  local ok, lualine = pcall(require, "lualine")
  if ok then
    pcall(lualine.refresh, { place = { "statusline" } })
  end
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function start_timer()
  if timer then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(
    DELAY_MS,
    FRAME_MS,
    vim.schedule_wrap(function()
      if count() == 0 then
        stop_timer()
      else
        frame = frame + 1
      end
      refresh()
    end)
  )
end

--- Statusline text, or "" when nothing has been pending longer than DELAY_MS.
function M.status()
  local now = vim.uv.now()
  local oldest
  for _, req in pairs(pending) do
    if not oldest or req.start < oldest.start then
      oldest = req
    end
  end
  if not oldest or now - oldest.start < DELAY_MS then
    return ""
  end
  local extra = count() > 1 and (" +" .. (count() - 1)) or ""
  return string.format(
    "%s %s: %s %.1fs%s",
    SPINNER[frame % #SPINNER + 1],
    oldest.client,
    oldest.label,
    (now - oldest.start) / 1000,
    extra
  )
end

function M.setup()
  local group = vim.api.nvim_create_augroup("yf_lsp_pending", { clear = true })

  vim.api.nvim_create_autocmd("LspRequest", {
    group = group,
    callback = function(ev)
      local data = ev.data or {}
      local req = data.request
      if not req then
        return
      end
      local key = data.client_id .. ":" .. tostring(data.request_id)
      if req.type == "pending" then
        local label = TRACKED[req.method]
        if not label then
          return
        end
        local client = vim.lsp.get_client_by_id(data.client_id)
        vim.uv.update_time()
        pending[key] = { label = label, client = client and client.name or "lsp", start = vim.uv.now() }
        start_timer()
      elseif pending[key] then
        -- "complete" or "cancel"
        pending[key] = nil
        if count() == 0 then
          stop_timer()
          refresh()
        end
      end
    end,
  })

  -- A crashed/stopped server never answers; don't spin forever.
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(ev)
      local prefix = ev.data.client_id .. ":"
      for key in pairs(pending) do
        if key:sub(1, #prefix) == prefix then
          pending[key] = nil
        end
      end
      if count() == 0 then
        stop_timer()
        refresh()
      end
    end,
  })
end

return M
