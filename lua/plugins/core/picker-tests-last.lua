-- Snacks picker: push results from test projects to the bottom of file,
-- grep, and LSP (references/implementations/definitions/symbols) lists.
--
-- A result is "test" when a *directory* in its path looks like a test
-- project/folder: `test`, `tests`, `__tests__`, or a name ending in
-- `.Tests`, `.IntegrationTests`, `.UnitTests`, `-tests`, `_test`, ... or
-- containing `.Test.` (e.g. `Dispute.Test.Common`). File names themselves are
-- not checked. Within each group the normal score ordering is kept, so the
-- best non-test match is still first - but every test match comes after
-- every non-test match.

-- Optional word before "Test(s)" in a suffix like `.IntegrationTests`.
local KINDS = { "", "unit", "integration", "functional", "e2e", "acceptance", "component", "contract", "architecture" }

local function is_test_dir(seg)
  seg = seg:lower()
  if seg == "test" or seg == "tests" or seg == "__tests__" then
    return true
  end
  if seg:find("[%.%-_]tests?[%.%-_]") then -- Foo.Test.Common
    return true
  end
  for _, kind in ipairs(KINDS) do -- Foo.Tests, Foo.IntegrationTests, foo-test
    if seg:find("[%.%-_]" .. kind .. "tests?$") then
      return true
    end
  end
  return false
end

local cache = {} ---@type table<string, boolean>

local function is_test_path(path)
  if not path or path == "" then
    return false
  end
  local dir = path:match("^(.*)[/\\]") or ""
  local hit = cache[dir]
  if hit == nil then
    hit = false
    for seg in dir:gmatch("[^/\\]+") do
      if is_test_dir(seg) then
        hit = true
        break
      end
    end
    cache[dir] = hit
  end
  return hit
end

local function mark(item)
  item.yf_test = is_test_path(item.file) and 1 or 0
end

local tests_last = {
  transform = mark,
  -- Snacks' default fields, with the test flag (0 before 1) first.
  sort = { fields = { "yf_test", "score:desc", "#text", "idx" } },
  -- Also apply the ordering before anything is typed (e.g. references).
  matcher = { sort_empty = true },
}

local sources = {
  "files",
  "git_files",
  "grep",
  "grep_word",
  "lsp_references",
  "lsp_implementations",
  "lsp_definitions",
  "lsp_type_definitions",
  "lsp_workspace_symbols",
}

return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}
    for _, name in ipairs(sources) do
      opts.picker.sources[name] = vim.tbl_deep_extend("force", opts.picker.sources[name] or {}, tests_last)
    end
  end,
}
