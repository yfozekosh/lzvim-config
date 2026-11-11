-- Feature/profile resolution for nvim.
--
-- A profile selects a set of features. Disabled features' plugins are never
-- added to the lazy.nvim spec (not merely disabled). Resolution order:
--   1. NVIM_PROFILE environment variable
--   2. ~/.config/yf-nvim/profile  (written by setup.sh)
--   3. "full" (default, reproduces the original behaviour)
--
-- Feature overrides (feature=on/off) may be supplied in
-- ~/.config/yf-nvim/features and are applied on top of the profile.

local M = {}

local STATE_DIR = os.getenv("YF_NVIM_STATE_DIR") or vim.fn.expand("~/.config/yf-nvim")

local PROFILES = {
  minimal = { "core", "shell", "tmux", "docker", "git" },
  work = { "core", "shell", "tmux", "docker", "git", "ai" },
  frontend = { "core", "shell", "tmux", "docker", "git", "frontend" },
  embedded = { "core", "shell", "tmux", "docker", "git", "build", "embedded" },
  dotnet = { "core", "shell", "tmux", "docker", "git", "dotnet" },
  full = {
    "core",
    "build",
    "shell",
    "tmux",
    "docker",
    "git",
    "node",
    "ai",
    "frontend",
    "dotnet",
    "embedded",
  },
}

local DEPS = {
  build = { "core" },
  node = { "core" },
  ai = { "core", "node" },
  frontend = { "core", "node" },
  dotnet = { "core" },
  embedded = { "core" },
  docker = { "tmux" },
  wsl = { "core" },
}

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
  if is_wsl() then
    features.wsl = true
  end
  return features
end

local function read_selection()
  local profile_name
  local overrides = {}
  local content = read_file(STATE_DIR .. "/features")
  if not content then
    return profile_name, overrides
  end
  for line in content:gmatch("[^\n]+") do
    line = vim.trim(line)
    local key, value = line:match("^([^=]+)=(.+)$")
    if key then
      key = vim.trim(key)
      value = vim.trim(value):lower()
      if key == "profile" then
        profile_name = value
      elseif value == "on" or value == "true" or value == "1" or value == "yes" then
        overrides[key] = true
      elseif value == "off" or value == "false" or value == "0" or value == "no" then
        overrides[key] = false
      end
    end
  end
  return profile_name, overrides
end

local function load_features()
  local features = base_features(M.current())
  if not env_profile() then
    local file_profile, overrides = read_selection()
    if file_profile and (file_profile == "custom" or PROFILES[file_profile]) then
      features = base_features(file_profile)
    end
    for key, enabled in pairs(overrides) do
      features[key] = enabled or nil
    end
  end

  features.core = true
  features = close_deps(features)
  if is_wsl() then
    features.wsl = true
  end
  return features
end

M._features = nil

function M.features()
  if not M._features then
    M._features = load_features()
  end
  return M._features
end

function M.has(name)
  return M.features()[name] == true
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
