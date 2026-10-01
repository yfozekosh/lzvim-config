-- Surfaces Roslyn project-load failures (missing/incompatible .NET SDK,
-- NuGet auth failures, etc.) as a `vim.notify` instead of silently sitting
-- in `~/.local/state/nvim/lsp.log` where they're easy to miss.
--
-- Background: the Roslyn language server can fail to load individual
-- `.csproj` files (e.g. wrong `dotnet` on PATH, or a private NuGet feed
-- returning 401) while still starting up and attaching just fine. When that
-- happens, same-file LSP features keep working but anything that needs
-- cross-project symbols (go-to-definition into another project, workspace
-- symbols, etc.) silently returns empty results. See
-- docs/dotnet-roslyn-troubleshooting.md for the full story.
local M = {}

--- @class RoslynDiagStatus
--- @field pattern string Lua pattern matched against the log message
--- @field title string Short notify title
--- @field hint string One-line remediation hint

--- @type RoslynDiagStatus[]
local KNOWN_ISSUES = {
  {
    pattern = "hostfxr_resolve_sdk2",
    title = ".NET SDK not found",
    hint = "Check `dotnet --version` / PATH / DOTNET_ROOT match the SDK pinned in global.json.",
  },
  {
    pattern = "compatible %.NET SDK was not found",
    title = ".NET SDK not found",
    hint = "Check `dotnet --version` / PATH / DOTNET_ROOT match the SDK pinned in global.json.",
  },
  {
    pattern = "401 %(Unauthorized%)",
    title = "NuGet auth failed (401)",
    hint = "Check that $nugetPAT is exported (see ~/.nugetPAT) and still valid.",
  },
  {
    pattern = "Unable to load the service index",
    title = "NuGet feed unreachable",
    hint = "Check network/VPN access and $nugetPAT for the private feed.",
  },
}

-- message -> true, purely to avoid re-processing an exact duplicate log
-- line twice (roslyn sometimes repeats the same message for the same
-- project).
local seen = {}

-- Every distinct project-load failure (known or not) gets batched per
-- "bucket" (either a known issue's title, or the generic fallback) and
-- flushed as a single notification after a short debounce, instead of one
-- popup per affected project.
--- @type table<string, { hint: string?, messages: string[], level: integer }>
local buckets = {}
local gen = 0

local function classify(message)
  for _, issue in ipairs(KNOWN_ISSUES) do
    if message:find(issue.pattern) then
      return issue
    end
  end
  return nil
end

local function flush()
  for title, bucket in pairs(buckets) do
    local count = #bucket.messages
    if count > 0 then
      local lines = {
        string.format("Roslyn: %s (%d project%s affected)", title, count, count == 1 and "" or "s"),
      }
      if bucket.hint then
        table.insert(lines, bucket.hint)
      end
      table.insert(lines, "First: " .. bucket.messages[1]:sub(1, 200))
      table.insert(lines, "See :RoslynDoctor and docs/dotnet-roslyn-troubleshooting.md")
      vim.notify(table.concat(lines, "\n"), bucket.level, { title = "roslyn.nvim" })
    end
  end
  buckets = {}
end

local function schedule_flush()
  gen = gen + 1
  local this_gen = gen
  vim.defer_fn(function()
    if this_gen == gen then
      flush()
    end
  end, 1500)
end

--- Wraps the default `window/logMessage` handler so known/likely-fatal
--- Roslyn project-load failures also show up as a batched `vim.notify`, not
--- just in `:LspLog`.
--- @param default_handler function
--- @return function
function M.wrap_log_message_handler(default_handler)
  return function(err, result, ctx, config)
    default_handler(err, result, ctx, config)

    local message = result and result.message
    if type(message) ~= "string" then
      return
    end

    -- Roslyn's design-time build failures come through as
    -- "[solution/open] [LanguageServerProjectSystem] Error while loading ..."
    if not message:find("Error while loading") and not message:find("Unauthorized") then
      return
    end

    if seen[message] then
      return
    end
    seen[message] = true

    local issue = classify(message)
    local title = issue and issue.title or "project load failure"
    local bucket = buckets[title]
    if not bucket then
      bucket = { hint = issue and issue.hint, messages = {}, level = issue and vim.log.levels.ERROR or vim.log.levels.WARN }
      buckets[title] = bucket
    end
    table.insert(bucket.messages, message)
    schedule_flush()
  end
end

--- Resets the "already notified" state. Mainly useful after fixing an issue
--- and restarting Roslyn, so a recurring error notifies again.
function M.reset()
  seen = {}
  buckets = {}
  gen = gen + 1 -- invalidate any in-flight debounce
end

--- Lightweight, synchronous sanity checks for the most common ways Roslyn
--- ends up half-broken. Exposed as `:RoslynDoctor`.
function M.doctor()
  local lines = {}
  local function report(ok, msg)
    table.insert(lines, string.format("%s %s", ok and "OK" or "FAIL", msg))
  end

  local dotnet_path = vim.fn.exepath("dotnet")
  if dotnet_path == "" then
    report(false, "`dotnet` not found on PATH")
  else
    local version = vim.fn.system({ "dotnet", "--version" }):gsub("%s+$", "")
    report(true, string.format("dotnet resolves to %s (version %s)", dotnet_path, version))
  end

  if vim.env.DOTNET_ROOT and vim.env.DOTNET_ROOT ~= "" then
    report(true, "DOTNET_ROOT=" .. vim.env.DOTNET_ROOT)
  else
    report(false, "DOTNET_ROOT is not set")
  end

  if vim.env.nugetPAT and vim.env.nugetPAT ~= "" then
    report(true, string.format("nugetPAT is set (%d chars)", #vim.env.nugetPAT))
  else
    report(false, "nugetPAT is not set (private NuGet feeds referencing %nugetPAT% will 401)")
  end

  local clients = vim.lsp.get_clients({ name = "roslyn" })
  if #clients == 0 then
    report(false, "no attached roslyn client for the current buffer")
  else
    for _, client in ipairs(clients) do
      report(true, string.format("roslyn client attached (id=%d, root_dir=%s)", client.id, client.config.root_dir or "?"))
    end
  end

  local ok, registry = pcall(require, "mason-registry")
  if ok and registry.has_package("roslyn") then
    local pkg = registry.get_package("roslyn")
    report(pkg:is_installed(), "Mason roslyn package installed")
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "RoslynDoctor" })
end

vim.api.nvim_create_user_command("RoslynDoctor", M.doctor, {
  desc = "Run sanity checks for a common Roslyn / dotnet SDK / NuGet setup issues",
})

return M
