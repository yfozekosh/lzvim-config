-- Event-loop stall recorder.
--
-- While nvim's main loop is blocked nothing can be drawn, so no spinner can
-- show "work" - but the stall can be measured afterwards: a repeating timer
-- that fires late means the loop was busy. Every stall longer than
-- THRESHOLD_MS is appended to $XDG_RUNTIME_DIR/nvim/stalls.log (tmpfs, next
-- to lsp.log) with the mode, filetype, recent keys, and any LSP requests
-- still pending, so it can be lined up with lsp.log timestamps.
--
-- Cost: one timer callback every INTERVAL_MS doing a clock read.
local M = {}

local INTERVAL_MS = 100
local THRESHOLD_MS = 250
local KEYS_KEPT = 12

local keys = {} ---@type string[]

local function log_path()
  local runtime = vim.env.XDG_RUNTIME_DIR
  local stat = runtime and runtime ~= "" and vim.uv.fs_stat(runtime)
  local dir = (stat and stat.type == "directory") and (runtime .. "/nvim") or vim.fn.stdpath("log")
  vim.fn.mkdir(dir, "p")
  return dir .. "/stalls.log"
end

local function pending_lsp()
  local out = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    for _, req in pairs(client.requests or {}) do
      if req.type == "pending" then
        out[#out + 1] = client.name .. ":" .. req.method
      end
    end
  end
  return table.concat(out, ",")
end

function M.setup()
  local path = log_path()

  vim.on_key(function(_, typed)
    if typed and typed ~= "" then
      keys[#keys + 1] = vim.fn.keytrans(typed)
      if #keys > KEYS_KEPT then
        table.remove(keys, 1)
      end
    end
  end, vim.api.nvim_create_namespace("yf_stall_log"))

  local timer = assert(vim.uv.new_timer())
  local expected = vim.uv.now() + INTERVAL_MS
  timer:start(INTERVAL_MS, INTERVAL_MS, function()
    -- Runs in the libuv callback: only cheap work here, then hand off.
    vim.uv.update_time()
    local now = vim.uv.now()
    local late = now - expected
    expected = now + INTERVAL_MS
    if late < THRESHOLD_MS then
      return
    end
    local sec, usec = vim.uv.gettimeofday()
    vim.schedule(function()
      local line = string.format(
        "[%s.%03d] stall %dms mode=%s ft=%s keys=%s lsp_pending=%s\n",
        os.date("%F %H:%M:%S", sec),
        math.floor(usec / 1000),
        late,
        vim.api.nvim_get_mode().mode,
        vim.bo.filetype,
        table.concat(keys, ""),
        pending_lsp()
      )
      local f = io.open(path, "a")
      if f then
        f:write(line)
        f:close()
      end
    end)
  end)
end

return M
