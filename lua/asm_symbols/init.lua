--- Project-wide completion from the linked ELF.
---
--- asm-lsp has no project index, so symbols defined in other assembly or C
--- files never appear. This module indexes the project's newest ELF with
--- `nm` and feeds the result to blink.cmp as a separate source.
local M = {}

local NM_CANDIDATES = {
  "riscv-none-elf-nm",
  "riscv64-unknown-elf-nm",
  "riscv32-unknown-elf-nm",
  "nm",
}

local FUNCTION_TYPES = { T = true, t = true, W = true, w = true }
local VARIABLE_TYPES = {
  D = true,
  d = true,
  B = true,
  b = true,
  G = true,
  g = true,
  S = true,
  s = true,
  C = true,
  c = true,
  R = true,
  r = true,
  V = true,
  v = true,
}
local CONSTANT_TYPES = { A = true, a = true }

--- @param symbol_type string
function M.kind_for(symbol_type)
  local kind = vim.lsp.protocol.CompletionItemKind
  if FUNCTION_TYPES[symbol_type] then
    return kind.Function
  end
  if VARIABLE_TYPES[symbol_type] then
    return kind.Variable
  end
  if CONSTANT_TYPES[symbol_type] then
    return kind.Constant
  end
  return kind.Text
end

--- @param output string
--- @return { name: string, type: string, address: string, size: integer|nil }[]
function M.parse_nm(output)
  local result = {}
  for line in (output or ""):gmatch("[^\r\n]+") do
    local name, symbol_type, address, size = line:match("^(%S+)%s+(%S)%s+(%x+)%s*(%x*)$")
    if name and symbol_type and address and symbol_type ~= "U" and symbol_type ~= "u" then
      local entry = { name = name, type = symbol_type, address = address }
      if size and size ~= "" then
        entry.size = tonumber(size, 16)
      end
      result[#result + 1] = entry
    end
  end
  return result
end

--- @param symbols table[]
--- @param elf string
--- @return lsp.CompletionItem[]
function M.to_items(symbols, elf)
  local kind = vim.lsp.protocol.CompletionItemKind
  local types = vim.lsp.protocol.InsertTextFormat
  local items = {}
  local seen = {}
  local basename = vim.fn.fnamemodify(elf, ":t")
  for _, sym in ipairs(symbols) do
    if not seen[sym.name] then
      seen[sym.name] = true
      local size_part = sym.size and (" (" .. sym.size .. " bytes)") or ""
      local detail = string.format("%s %s · 0x%s · %s%s", sym.type, M.kind_label(sym.type), sym.address, basename, size_part)
      local documentation = string.format(
        "`%s`\n\n%s symbol in `%s` at `0x%s`.",
        sym.name,
        M.kind_label(sym.type),
        elf,
        sym.address
      )
      items[#items + 1] = {
        label = sym.name,
        filterText = sym.name,
        kind = M.kind_for(sym.type),
        detail = detail,
        documentation = { kind = "markdown", value = documentation },
        insertText = sym.name,
        insertTextFormat = types.PlainText,
      }
    end
  end
  return items
end

function M.kind_label(symbol_type)
  if FUNCTION_TYPES[symbol_type] then
    return "function"
  end
  if VARIABLE_TYPES[symbol_type] then
    return "variable"
  end
  if CONSTANT_TYPES[symbol_type] then
    return "constant"
  end
  return "symbol"
end

--- @param configured string|string[]|nil
--- @return string[]|nil, string[]
function M.resolve_nm(configured)
  if type(configured) == "table" then
    return vim.list_extend({}, configured), NM_CANDIDATES
  end
  if type(configured) == "string" and configured ~= "" then
    if vim.fn.executable(configured) == 1 then
      return { configured }, NM_CANDIDATES
    end
    return nil, NM_CANDIDATES
  end
  for _, candidate in ipairs(NM_CANDIDATES) do
    if vim.fn.executable(candidate) == 1 then
      return { candidate }, NM_CANDIDATES
    end
  end
  return nil, NM_CANDIDATES
end

--- @param start_path string
--- @param configured string|nil
--- @return string|nil
function M.find_newest_elf(start_path, configured)
  local disasm_config = require("disasm.config")
  local candidates = disasm_config.find_elf({ elf = configured }, start_path or "")
  if type(candidates) ~= "table" then
    return nil
  end
  local best, best_key
  for _, candidate in ipairs(candidates) do
    local stat = vim.uv.fs_stat(candidate)
    if stat then
      local key = tostring(stat.mtime.sec) .. ":" .. tostring(stat.mtime.nsec)
      if not best_key or key > best_key then
        best_key = key
        best = candidate
      end
    end
  end
  if configured and type(configured) == "string" and configured ~= "" and not best then
    -- configured path that does not exist: do not silently pick another file
    return nil
  end
  return best
end

local function settings(opts)
  local cfg = vim.g.asm_symbols
  if type(cfg) ~= "table" then
    cfg = {}
  end
  return vim.tbl_extend("force", cfg, opts or {})
end

local function mtime_key(elf)
  local stat = vim.uv.fs_stat(elf)
  if not stat then
    return nil
  end
  return elf .. "\0" .. tostring(stat.mtime.sec) .. ":" .. tostring(stat.mtime.nsec) .. ":" .. tostring(stat.size)
end

local cache = {
  key = nil,
  elf = nil,
  items = nil,
  pending = nil,
}

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

  local cfg = settings(self.opts)
  local elf = M.find_newest_elf(start, cfg.elf)
  if not elf then
    callback(empty)
    return
  end

  local nm_argv = M.resolve_nm(cfg.nm)
  if not nm_argv then
    callback(empty)
    return
  end

  local key = mtime_key(elf)
  if not key then
    callback(empty)
    return
  end

  -- Fresh cache: serve immediately and refresh in the background when the
  -- ELF has changed on disk.
  if cache.items and cache.elf == elf then
    callback({ items = vim.deepcopy(cache.items), is_incomplete_forward = false, is_incomplete_backward = false })
    if cache.key ~= key then
      M.refresh_cache(elf, nm_argv, key)
    end
    return
  end

  -- Coalesce concurrent requests for the same ELF/mtime.
  if cache.pending and cache.pending.key == key then
    table.insert(cache.pending.callbacks, callback)
    return function()
      for i, cb in ipairs(cache.pending.callbacks) do
        if cb == callback then
          table.remove(cache.pending.callbacks, i)
          break
        end
      end
    end
  end

  cache.pending = { key = key, callbacks = { callback } }
  local argv = vim.list_extend(vim.list_extend({}, nm_argv), { "--defined-only", "-S", "--format=posix", elf })
  vim.system(argv, { text = true }, function(res)
    vim.schedule(function()
      local pending = cache.pending
      cache.pending = nil
      local items = {}
      if res.code == 0 then
        items = M.to_items(M.parse_nm(res.stdout or ""), elf)
      end
      cache.key = key
      cache.elf = elf
      cache.items = items
      local result = { items = vim.deepcopy(items), is_incomplete_forward = false, is_incomplete_backward = false }
      local callbacks = pending and pending.callbacks or {}
      for _, cb in ipairs(callbacks) do
        cb(result)
      end
    end)
  end)

  return function()
    if cache.pending and cache.pending.key == key then
      for i, cb in ipairs(cache.pending.callbacks) do
        if cb == callback then
          table.remove(cache.pending.callbacks, i)
          break
        end
      end
    end
  end
end

function M.refresh_cache(elf, nm_argv, key)
  if cache.pending then
    return
  end
  cache.pending = { key = key, callbacks = {} }
  local argv = vim.list_extend(vim.list_extend({}, nm_argv), { "--defined-only", "-S", "--format=posix", elf })
  vim.system(argv, { text = true }, function(res)
    vim.schedule(function()
      cache.pending = nil
      if res.code == 0 then
        cache.key = key
        cache.elf = elf
        cache.items = M.to_items(M.parse_nm(res.stdout or ""), elf)
      end
    end)
  end)
end

function M.new(opts)
  return source.new(opts)
end

function M.doctor_lines(bufnr)
  local lines = {}
  local start = vim.api.nvim_buf_get_name(bufnr or vim.api.nvim_get_current_buf())
  if start == "" then
    start = vim.fn.getcwd()
  end
  local cfg = settings({})
  local elf = M.find_newest_elf(start, cfg.elf)
  if not elf then
    table.insert(lines, "INFO project symbols: no ELF found (build first; see :DisasmOpen)")
    return lines
  end
  local nm_argv = M.resolve_nm(cfg.nm)
  if not nm_argv then
    table.insert(lines, "INFO project symbols: no nm found for " .. elf)
    return lines
  end
  local result = vim.system(vim.list_extend(vim.list_extend({}, nm_argv), { "--defined-only", "-S", "--format=posix", elf }), { text = true }):wait()
  local count = 0
  if result.code == 0 then
    count = #M.parse_nm(result.stdout or "")
  end
  table.insert(lines, string.format("OK project symbols: %d symbol(s) from %s (nm: %s)", count, elf, table.concat(nm_argv, " ")))
  return lines
end

return M