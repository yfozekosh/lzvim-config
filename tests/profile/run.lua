-- Run from the repo root:
--   nvim --headless -u NONE -l tests/profile/run.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Isolate from the real ~/.config/yf-nvim selection file. Keep the scratch
-- directory inside the repo: /tmp is a small tmpfs on the target machine.
local test_home = vim.fn.getcwd() .. "/.tmp/profile-test"
vim.fn.delete(test_home, "rf")
vim.fn.mkdir(test_home, "p")
vim.env.YF_NVIM_STATE_DIR = test_home

local function check(profile, expected_on, expected_off)
  vim.env.NVIM_PROFILE = profile
  package.loaded["config.profile"] = nil
  local P = require("config.profile")
  assert(P.current() == profile, ("expected profile %s, got %s"):format(profile, P.current()))
  for _, feature in ipairs(expected_on) do
    assert(P.has(feature), ("%s should enable %s"):format(profile, feature))
  end
  for _, feature in ipairs(expected_off) do
    assert(not P.has(feature), ("%s should not enable %s"):format(profile, feature))
  end
end

check("minimal", { "core", "shell", "tmux", "docker", "git" }, { "build", "node", "ai", "frontend", "dotnet", "embedded" })
check("work", { "core", "ai", "node", "docker" }, { "build", "frontend", "dotnet", "embedded" })
check("frontend", { "core", "frontend", "node", "docker" }, { "build", "ai", "dotnet", "embedded" })
check("embedded", { "core", "build", "embedded", "docker" }, { "node", "ai", "frontend", "dotnet" })
check("dotnet", { "core", "dotnet", "docker" }, { "build", "node", "ai", "frontend", "embedded" })
check(
  "full",
  { "core", "build", "shell", "tmux", "docker", "git", "node", "ai", "frontend", "dotnet", "embedded" },
  {}
)

-- A custom selection written by an older version must not inherit new
-- features (build/frontend/node) from the current "full" preset.
vim.env.NVIM_PROFILE = nil
vim.fn.mkdir(test_home, "p")
vim.fn.writefile({ "custom" }, test_home .. "/profile")
vim.fn.writefile({ "profile=custom", "core=on", "shell=on", "tmux=on", "git=on", "ai=on" }, test_home .. "/features")
package.loaded["config.profile"] = nil
local custom = require("config.profile")
assert(custom.current() == "custom", "expected custom profile")
assert(custom.has("core") and custom.has("ai") and custom.has("node"), "custom should keep core/ai/node")
assert(not custom.has("build"), "custom should not inherit build")
assert(not custom.has("frontend"), "custom should not inherit frontend")
assert(not custom.has("docker"), "custom should not inherit docker")

-- NVIM_PROFILE is a full override: a persisted custom selection must not
-- disable features from the requested profile.
vim.fn.writefile({ "frontend=off", "profile=custom" }, test_home .. "/features")
vim.env.NVIM_PROFILE = "frontend"
package.loaded["config.profile"] = nil
local override = require("config.profile")
assert(override.current() == "frontend", "NVIM_PROFILE should win over persisted profile")
assert(override.has("frontend") and override.has("node") and override.has("docker"), "NVIM_PROFILE should enable frontend deps")
assert(not override.has("ai") and not override.has("build"), "NVIM_PROFILE should not inherit custom features")

vim.fn.delete(test_home, "rf")
print("profile tests OK")
