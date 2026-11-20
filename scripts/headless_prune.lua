-- Headless prune: removes nvim state that the current profile/config no
-- longer declares, so switching profiles (or dropping a language from the
-- config) actually frees the disk/startup cost:
--   1. lazy.nvim plugins that are no longer in the spec (`:Lazy clean`)
--   2. Mason packages not requested by any loaded config
--   3. nvim-treesitter parsers not in `ensure_installed` (+ their deps)
--
-- Run via:
--   nvim --headless -c "luafile scripts/headless_prune.lua"
-- Set YF_NVIM_PRUNE_DRY=1 to only print what would be removed.
-- Used by setup.sh's `prune_nvim_state` migration (runs every setup).
--
-- Safety: if the "wanted" set for Mason or treesitter can't be computed
-- (plugin missing, API changed, empty result), that step is skipped rather
-- than uninstalling everything.

local dry = os.getenv("YF_NVIM_PRUNE_DRY") == "1"

local function say(msg)
  io.stdout:write("headless_prune: " .. msg .. "\n")
end

local function set_of(list)
  local s = {}
  for _, v in ipairs(list or {}) do
    s[v] = true
  end
  return s
end

-- 1. lazy.nvim -------------------------------------------------------------
-- `lazy.clean` also rewrites lazy-lock.json and drops entries for plugins
-- that aren't in *this machine's* profile. The lockfile is shared across
-- profiles in git, so keep its original content.
local ok_lazy, lazy = pcall(require, "lazy")
if ok_lazy then
  local Config = require("lazy.core.config")
  local names = {}
  for _, p in ipairs(Config.to_clean) do
    names[#names + 1] = p.name
  end
  table.sort(names)
  if #names == 0 then
    say("lazy: nothing to clean")
  elseif dry then
    say("lazy: would remove " .. table.concat(names, ", "))
  else
    local lockfile = Config.options.lockfile
    local f = io.open(lockfile, "rb")
    local lock_content = f and f:read("*a")
    if f then
      f:close()
    end
    lazy.clean({ wait = true, show = false })
    if lock_content then
      local w = assert(io.open(lockfile, "wb"))
      w:write(lock_content)
      w:close()
    end
    say("lazy: removed " .. table.concat(names, ", "))
  end
else
  say("lazy.nvim not found, skipping plugin clean")
end

-- Force-load the plugins whose opts we read below.
pcall(function()
  require("lazy").load({ plugins = { "mason.nvim", "nvim-lspconfig", "mason-lspconfig.nvim", "nvim-treesitter" } })
end)

-- 2. Mason ------------------------------------------------------------------
local function wanted_mason()
  if not _G.LazyVim then
    return nil, "LazyVim not loaded"
  end
  local wanted = {}
  for _, name in ipairs(LazyVim.opts("mason.nvim").ensure_installed or {}) do
    wanted[name] = true
  end

  -- LSP servers: mirror LazyVim's lsp/init.lua logic (enabled, mason ~= false,
  -- known to mason-lspconfig), then map lspconfig name -> Mason package.
  local ok_map, mappings = pcall(require, "mason-lspconfig.mappings")
  if not ok_map then
    return nil, "mason-lspconfig.mappings unavailable"
  end
  local to_pkg = mappings.get_mason_map().lspconfig_to_package
  local servers = LazyVim.opts("nvim-lspconfig").servers or {}
  local extra = LazyVim.opts("mason-lspconfig.nvim").ensure_installed or {}
  for server, sopts in pairs(servers) do
    if server ~= "*" and sopts then
      sopts = sopts == true and {} or sopts
      if sopts.enabled ~= false and sopts.mason ~= false and to_pkg[server] then
        wanted[to_pkg[server]] = true
      end
    end
  end
  for _, server in ipairs(extra) do
    wanted[to_pkg[server] or server] = true
  end

  -- Debug adapters requested via mason-nvim-dap.
  local dap_opts = LazyVim.opts("mason-nvim-dap.nvim")
  if dap_opts and dap_opts.ensure_installed then
    local ok_src, src = pcall(require, "mason-nvim-dap.mappings.source")
    for _, name in ipairs(dap_opts.ensure_installed) do
      wanted[(ok_src and src.nvim_dap_to_package and src.nvim_dap_to_package[name]) or name] = true
    end
  end

  -- Installed imperatively by lua/plugins/dotnet/roslyn.lua.
  local ok_profile, profile = pcall(require, "config.profile")
  if ok_profile and profile.has("dotnet") then
    -- Official-registry name, plus the legacy Crashdummyy-registry name
    -- still installed on older machines (roslyn.lua accepts either).
    wanted["roslyn-language-server"] = true
    wanted["roslyn"] = true
  end

  if next(wanted) == nil then
    return nil, "computed wanted set is empty"
  end
  return wanted
end

local ok_mr, mr = pcall(require, "mason-registry")
if ok_mr then
  local wanted, err = wanted_mason()
  if not wanted then
    say("mason: skipping prune (" .. err .. ")")
  else
    local remove = {}
    for _, name in ipairs(mr.get_installed_package_names()) do
      if not wanted[name] then
        remove[#remove + 1] = name
      end
    end
    table.sort(remove)
    if #remove == 0 then
      say("mason: nothing to remove")
    elseif dry then
      say("mason: would remove " .. table.concat(remove, ", "))
    else
      for _, name in ipairs(remove) do
        local ok_pkg, pkg = pcall(mr.get_package, name)
        if ok_pkg and pkg:is_installed() then
          pcall(function()
            pkg:uninstall()
          end)
        end
      end
      vim.wait(120000, function()
        for _, name in ipairs(remove) do
          local ok_pkg, pkg = pcall(mr.get_package, name)
          if ok_pkg and pkg:is_installed() then
            return false
          end
        end
        return true
      end, 200)
      say("mason: removed " .. table.concat(remove, ", "))
    end
  end
else
  say("mason-registry not found, skipping Mason prune")
end

-- 3. Treesitter parsers -----------------------------------------------------
local ok_ts, ts = pcall(require, "nvim-treesitter")
local ok_tscfg, tscfg = pcall(require, "nvim-treesitter.config")
if ok_ts and ok_tscfg and _G.LazyVim and tscfg.norm_languages then
  local ensure = LazyVim.opts("nvim-treesitter").ensure_installed or {}
  -- norm_languages also pulls in `requires` deps (e.g. tsx -> ecma/jsx).
  local wanted = set_of(tscfg.norm_languages(ensure))
  if next(wanted) == nil then
    say("treesitter: skipping prune (computed wanted set is empty)")
  else
    local remove = {}
    for _, lang in ipairs(tscfg.get_installed("parsers")) do
      if not wanted[lang] then
        remove[#remove + 1] = lang
      end
    end
    table.sort(remove)
    if #remove == 0 then
      say("treesitter: nothing to remove")
    elseif dry then
      say("treesitter: would remove " .. table.concat(remove, ", "))
    else
      local task = ts.uninstall(remove)
      if task and task.wait then
        task:wait(120000)
      end
      say("treesitter: removed " .. table.concat(remove, ", "))
    end
  end
else
  say("nvim-treesitter (main branch API) not found, skipping parser prune")
end

vim.cmd("qa")
