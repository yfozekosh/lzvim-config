-- Feature/profile resolution for nvim.
--
-- A profile selects a set of features. Disabled features' plugins are never
-- added to the lazy.nvim spec (not merely disabled). Resolution order:
--   1. NVIM_PROFILE environment variable
--   2. ~/.config/yf-nvim/profile  (written by setup.sh)
--   3. "full" (default, reproduces the original behaviour)
--
-- Feature definitions and profiles live in the shared features.json manifest
-- at the repository root, so Python setup and Neovim cannot drift apart.
-- Feature overrides (feature=on/off) may be supplied in
-- ~/.config/yf-nvim/features and are applied on top of the profile.

local M = {}

local STATE_DIR = os.getenv("YF_NVIM_STATE_DIR") or vim.fn.expand("~/.config/yf-nvim")

local function repo_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return vim.fn.fnamemodify(source, ":p:h:h:h")
end

local manifest_path = repo_root() .. "/features.json"
local manifest_file = assert(io.open(manifest_path, "r"), "missing feature manifest: " .. manifest_path)
local manifest = vim.json.decode(manifest_file:read("*a"))
manifest_file:close()

local FEATURES = manifest.features or {}
local PROFILES = manifest.profiles or {}
local ALIASES = manifest.aliases or {}
local LEGACY_CORE_IMPLIES = manifest.legacy_core_implies or {}

local DEPS = {}
local AUTO = {}
for fid, data in pairs(FEATURES) do
  DEPS[fid] = data.depends or {}
  if data.auto then
    AUTO[#AUTO + 1] = fid
  end
end
table.sort(AUTO)

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- An explicit NVIM_PROFILE is a full override: ignore the persisted
--- selection so profile smoke tests and temporary sessions are deterministic.
local function env_profile()
  local name = os.getenv("NVIM_PROFILE")
  if not name or name == "" or not PROFILES[name] then
    return nil
  end
  return name
end

local function is_wsl()
  local f = io.open("/proc/version", "r")
  if not f then
    return false
  end
  local content = f:read("*a")
  f:close()
  return content:lower():find("microsoft") ~= nil
end

local function close_deps(features)
  local result = {}
  for f, _ in pairs(features) do
    result[f] = true
  end
  local changed = true
  while changed do
    changed = false
    for name, _ in pairs(result) do
      for _, dep in ipairs(DEPS[name] or {}) do
        if not result[dep] then
          result[dep] = true
          changed = true
        end
      end
    end
  end
  return result
end

function M.current()
  local name = env_profile()
  if not name then
    local content = read_file(STATE_DIR .. "/profile")
    if content then
      name = vim.trim(content)
    end
  end
  if not name or name == "" then
    name = "full"
  elseif name ~= "custom" and not PROFILES[name] then
    name = "full"
  end
  return name
end

local function base_features(profile_name)
  local features = {}
  -- "custom" means the features file is authoritative. Unknown features added
  -- by a newer version stay off until the user enables them.
  for _, f in ipairs(PROFILES[profile_name] or {}) do
    features[f] = true
  end
  if profile_name ~= "custom" and is_wsl() then
    for _, fid in ipairs(AUTO) do
      features[fid] = true
    end
  end
  return features
end

local function read_selection()
  local profile_name
  local entries = {}
  local content = read_file(STATE_DIR .. "/features")
  if not content then
    return profile_name, entries
  end
  for line in content:gmatch("[^\n]+") do
    line = vim.trim(line)
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      key = vim.trim(key)
      value = vim.trim(value):lower()
      if key == "profile" then
        profile_name = value
      elseif value == "on" or value == "true" or value == "1" or value == "yes" then
        entries[#entries + 1] = { key = key, enabled = true }
      elseif value == "off" or value == "false" or value == "0" or value == "no" then
        entries[#entries + 1] = { key = key, enabled = false }
      end
    end
  end
  return profile_name, entries
end

local function load_features()
  local features = base_features(M.current())
  if not env_profile() then
    local file_profile, entries = read_selection()
    if file_profile and (file_profile == "custom" or PROFILES[file_profile]) then
      features = base_features(file_profile)
    end

    local explicit = {}
    for _, entry in ipairs(entries) do
      local targets = ALIASES[entry.key] or { entry.key }
      for _, fid in ipairs(targets) do
        if FEATURES[fid] then
          explicit[fid] = entry.enabled
          if entry.enabled then
            features[fid] = true
          else
            features[fid] = nil
          end
        end
      end
    end

    local custom = file_profile == "custom" or (file_profile == nil and M.current() == "custom")
    if custom then
      -- Before the nvim split, bootstrap/prune lived in core. Keep existing
      -- custom selections working unless they explicitly disabled nvim.
      for _, fid in ipairs(LEGACY_CORE_IMPLIES) do
        if explicit[fid] == nil and explicit.core == true then
          features[fid] = true
        end
      end
      -- Platform features are environment defaults; an explicit off entry
      -- (written by the interactive selector) wins.
      if is_wsl() then
        for _, fid in ipairs(AUTO) do
          if explicit[fid] ~= false then
            features[fid] = true
          end
        end
      end
    end
  end

  if not is_wsl() then
    for _, fid in ipairs(AUTO) do
      features[fid] = nil
    end
  end

  features.core = true
  return close_deps(features)
end

M._features = nil

function M.features()
  if not M._features then
    M._features = load_features()
  end
  return M._features
end

function M.has(name)
  local features = M.features()
  if features[name] == true then
    return true
  end
  -- Backward compatibility for callers/configs that still ask for an old
  -- aggregate feature name. The canonical features remain in M.list().
  for _, fid in ipairs(ALIASES[name] or {}) do
    if features[fid] == true then
      return true
    end
  end
  return false
end

function M.list()
  local out = {}
  for k, v in pairs(M.features()) do
    if v then
      table.insert(out, k)
    end
  end
  table.sort(out)
  return out
end

return M
