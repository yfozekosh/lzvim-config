local M = {}

local uv = vim.uv or vim.loop

-- file cache: path -> { sec=..., nsec=..., is_test=... }
local file_cache = {}

-- compiled attribute regex cache
local attr_regex_cache = {
  signature = nil,
  regex = nil,
}

-------------------------------------------------------
-- Utilities
-------------------------------------------------------

local function stat_mtime(path)
  local st = uv.fs_stat(path)
  if not st or not st.mtime then
    return nil
  end

  local m = st.mtime
  if type(m) == "table" then
    return m.sec or 0, m.nsec or 0
  end

  return m, 0
end

local function re_escape(s)
  return (tostring(s):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\])", "\\%1"))
end

local function build_signature(all_attrs, custom_args)
  local parts = {}

  for _, a in ipairs(all_attrs or {}) do
    parts[#parts + 1] = "S:" .. tostring(a)
  end

  if custom_args then
    local keys = {}
    for k in pairs(custom_args) do
      keys[#keys + 1] = k
    end
    table.sort(keys)

    for _, k in ipairs(keys) do
      parts[#parts + 1] = "K:" .. tostring(k)
      for _, v in ipairs(custom_args[k] or {}) do
        parts[#parts + 1] = "C:" .. tostring(v)
      end
    end
  end

  return table.concat(parts, "\n")
end

local function ensure_attr_regex(all_attrs, custom_args)
  local sig = build_signature(all_attrs, custom_args)

  if attr_regex_cache.signature == sig and attr_regex_cache.regex then
    return attr_regex_cache.regex
  end

  local attrs = {}

  for _, a in ipairs(all_attrs or {}) do
    attrs[#attrs + 1] = re_escape(a)
  end

  if custom_args then
    for _, arr in pairs(custom_args) do
      for _, v in ipairs(arr or {}) do
        attrs[#attrs + 1] = re_escape(v)
      end
    end
  end

  if #attrs == 0 then
    attr_regex_cache.signature = sig
    attr_regex_cache.regex = nil
    return nil
  end

  -- Match "[" followed by attribute name
  local regex = "\\[(" .. table.concat(attrs, "|") .. ")"

  attr_regex_cache.signature = sig
  attr_regex_cache.regex = regex

  return regex
end

local function rg_quiet_match(regex, path)
  local cmd = { "rg", "-q", "--no-messages", "-e", regex, path }

  if vim.system then
    local res = vim.system(cmd, { text = true }):wait()
    return res.code == 0
  end

  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

-------------------------------------------------------
-- Public API
-------------------------------------------------------

function M.is_test_file(path, all_attrs, custom_attrs)
  if not (vim.endswith(path, ".cs") or vim.endswith(path, ".fs")) then
    return false
  end

  local sec, nsec = stat_mtime(path)
  if not sec then
    return false
  end

  local cached = file_cache[path]
  if cached and cached.sec == sec and cached.nsec == nsec then
    return cached.is_test
  end

  local regex = ensure_attr_regex(all_attrs, custom_attrs)
  if not regex then
    file_cache[path] = { sec = sec, nsec = nsec, is_test = false }
    return false
  end

  local ok = rg_quiet_match(regex, path)

  file_cache[path] = {
    sec = sec,
    nsec = nsec,
    is_test = ok,
  }

  return ok
end

return M
