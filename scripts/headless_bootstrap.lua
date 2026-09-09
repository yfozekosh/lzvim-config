-- Headless bootstrap: installs all lazy.nvim plugins, treesitter parsers,
-- and Mason-managed LSP servers/tools without requiring an interactive
-- session. Run via:
--   nvim --headless -c "luafile scripts/headless_bootstrap.lua"
-- Used by setup.sh's `bootstrap_nvim_plugins` migration so a fresh machine
-- ends up with a fully working nvim (no first-launch wait for plugins).

-- 1. Install/update all plugins and treesitter parsers. `wait = true` blocks
-- until the sync (install + update + clean) is fully done, unlike the
-- `:Lazy sync` command which only queues the work. Retry a few times since
-- a flaky network can leave individual plugin clones/checkouts broken;
-- re-running sync retries just the plugins that didn't finish.
local ok_lazy, lazy = pcall(require, "lazy")
if ok_lazy then
  local Plugin = require("lazy.core.plugin")
  for attempt = 1, 3 do
    lazy.sync({ wait = true, show = false })
    Plugin.update_state()
    local all_ok = true
    for _, plugin in pairs(require("lazy.core.config").plugins) do
      if plugin._.installed == false then
        all_ok = false
      end
    end
    if all_ok then
      break
    end
    vim.notify(("headless_bootstrap: retrying lazy sync (attempt %d/3) after incomplete installs"):format(attempt))
  end
else
  vim.notify("headless_bootstrap: lazy.nvim not found, skipping plugin sync", vim.log.levels.WARN)
end

-- 2. Several plugins register their Mason `ensure_installed` tools only once
-- loaded (mason.nvim is cmd-loaded, mason-lspconfig loads alongside
-- nvim-lspconfig). Force-load them so those installs get queued.
pcall(function()
  require("lazy").load({ plugins = { "mason.nvim", "nvim-lspconfig", "mason-lspconfig.nvim" } })
end)

-- 3. Wait for Mason to finish installing every queued package (LSP servers,
-- formatters, linters, debug adapters, etc.), so setup.sh doesn't exit while
-- installs are still running in the background.
local ok_mr, mr = pcall(require, "mason-registry")
if ok_mr then
  if mr.refresh then
    local refreshed = false
    mr.refresh(function()
      refreshed = true
    end)
    vim.wait(30000, function()
      return refreshed
    end, 100)
  end
  vim.wait(600000, function()
    for _, pkg in ipairs(mr.get_all_packages()) do
      if pkg:is_installing() then
        return false
      end
    end
    return true
  end, 200)
else
  vim.notify("headless_bootstrap: mason-registry not found, skipping Mason wait", vim.log.levels.WARN)
end

vim.cmd("qa")
