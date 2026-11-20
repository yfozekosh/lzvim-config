-- LSP client logging tuned for diagnosing slow requests (gd/gI/hover) without
-- slowing the editor down.
--
-- * Level DEBUG, so every request/response is recorded.
-- * The default formatter runs vim.inspect() on every full payload (Roslyn
--   completion lists, semantic tokens, diagnostics...) on the main loop.
--   DEBUG/TRACE entries are summarised instead: id, method, error, and
--   result item count. WARN/ERROR keep the full default formatting.
-- * Millisecond timestamps (the default is whole seconds), so request ->
--   response latency can be read straight from the log.
-- * The file lives on tmpfs ($XDG_RUNTIME_DIR, e.g. /run/user/1000) when
--   available, so it costs no disk I/O; it is cleared on reboot / `wsl
--   --shutdown`. Falls back to stdpath("log"). `:LspLog` opens whichever is
--   in use. Rotated on startup once it exceeds 50 MB (one .old copy).
local M = {}

local MAX_BYTES = 50 * 1024 * 1024

local function log_path()
  local runtime = vim.env.XDG_RUNTIME_DIR
  local stat = runtime and runtime ~= "" and vim.uv.fs_stat(runtime)
  if stat and stat.type == "directory" then
    local dir = runtime .. "/nvim"
    vim.fn.mkdir(dir, "p")
    return dir .. "/lsp.log"
  end
  return vim.fn.stdpath("log") .. "/lsp.log"
end

local function summarize(v)
  if type(v) ~= "table" then
    if type(v) == "function" then
      return "<fn>"
    end
    return tostring(v)
  end
  local parts = {}
  if v.id ~= nil then
    parts[#parts + 1] = "id=" .. tostring(v.id)
  end
  if v.method then
    parts[#parts + 1] = "method=" .. tostring(v.method)
  end
  if v.error then
    parts[#parts + 1] = "error=" .. vim.inspect(v.error, { newline = " ", indent = "" })
  end
  if v.result ~= nil then
    local r = v.result
    if type(r) == "table" then
      local n = #r > 0 and #r or (type(r.items) == "table" and #r.items) or nil
      parts[#parts + 1] = n and ("result=[" .. n .. " items]") or "result={...}"
    else
      parts[#parts + 1] = "result=" .. tostring(r)
    end
  end
  if #parts == 0 then
    return "{...}"
  end
  return "{" .. table.concat(parts, " ") .. "}"
end

local function timestamp()
  local sec, usec = vim.uv.gettimeofday()
  return os.date("%F %H:%M:%S", sec) .. string.format(".%03d", math.floor(usec / 1000))
end

function M.setup()
  local log = vim.lsp.log
  local path = log_path()

  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > MAX_BYTES then
    vim.uv.fs_rename(path, path .. ".old")
  end

  -- Private API, but the only way to relocate the file; guarded so a future
  -- Neovim that drops it just keeps the default location.
  if log._set_filename then
    log._set_filename(path)
  end

  log.set_level("debug")

  log.set_format_func(function(level, ...)
    local levelnr = log.levels[level]
    if levelnr < log.get_level() then
      return nil
    end
    local full = levelnr >= log.levels.WARN
    local parts = { string.format("[%s][%s]", level, timestamp()) }
    for i = 1, select("#", ...) do
      local arg = select(i, ...)
      if arg == nil then
        parts[#parts + 1] = "nil"
      elseif full then
        parts[#parts + 1] = vim.inspect(arg, { newline = " ", indent = "" })
      else
        parts[#parts + 1] = summarize(arg)
      end
    end
    return table.concat(parts, "\t") .. "\n"
  end)
end

return M
