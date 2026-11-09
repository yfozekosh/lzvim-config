local M = {}

M.defaults = {
  objdump = nil,
  elf = nil,
  args = { "-d", "-l", "-C", "--no-show-raw-insn" },
  auto_scroll = true,
  highlight = "Visual",
  winbar = true,
  auto_refresh = true,
  cycles = true,
  cycle_view = "off",
  show_sizes = false,
  flash_start = 0x00000000,
  flash_end = 0x00004000,
  data_is_flash = false,
}

local OBJDUMP_CANDIDATES = {
  "riscv-none-elf-objdump",
  "riscv64-unknown-elf-objdump",
  "riscv32-unknown-elf-objdump",
  "objdump",
}

local ROOT_MARKERS = { ".git", "Makefile", "link.ld" }

function M.setup(user_opts)
  local config = vim.deepcopy(M.defaults)
  if type(user_opts) == "table" then
    for key, value in pairs(user_opts) do
      config[key] = value
    end
  end
  return config
end

-- A second objdump run with raw instruction bytes gives exact instruction
-- sizes even at function ends, where the next-address heuristic cannot help.
function M.raw_args(args)
  local result = {}
  for _, arg in ipairs(args or {}) do
    if arg ~= "--no-show-raw-insn" then
      result[#result + 1] = arg
    end
  end
  result[#result + 1] = "--show-raw-insn"
  return result
end

function M.make_flash_check(config)
  if type(config.is_flash) == "function" then
    return config.is_flash
  end
  local first = tonumber(config.flash_start) or 0x00000000
  local last = tonumber(config.flash_end) or 0x00004000
  return function(addr)
    return addr >= first and addr < last
  end
end

function M.roots_for(elf_path)
  local elf_dir = vim.fn.fnamemodify(elf_path, ":p:h")
  local project = vim.fs.root(elf_path, ROOT_MARKERS)
  if not project or project == "" then
    project = elf_dir
  end
  return {
    project = vim.fs.normalize(project),
    elf_dir = vim.fs.normalize(elf_dir),
    cwd = vim.fs.normalize(vim.fn.getcwd()),
  }
end

function M.find_elf(config, start_path)
  if type(config.elf) == "function" then
    local result = config.elf()
    if type(result) == "string" then
      return { vim.fs.normalize(result) }
    end
  elseif type(config.elf) == "string" and config.elf ~= "" then
    return { vim.fs.normalize(config.elf) }
  end

  local root = vim.fs.root(start_path, ROOT_MARKERS)
  if not root or root == "" then
    root = vim.fn.fnamemodify(start_path, ":p:h")
  end

  local patterns = { "out/*.elf", "build/*.elf", "*.elf" }
  local found = {}
  local seen = {}
  for _, pattern in ipairs(patterns) do
    local matches = vim.fn.globpath(root, pattern, false, true)
    for _, match in ipairs(matches) do
      if not seen[match] then
        seen[match] = true
        found[#found + 1] = vim.fs.normalize(match)
      end
    end
  end
  table.sort(found)
  return found
end

function M.resolve_objdump(config)
  local configured = config.objdump
  if type(configured) == "table" then
    return vim.list_extend({}, configured), OBJDUMP_CANDIDATES
  end
  if type(configured) == "string" and configured ~= "" then
    if vim.fn.executable(configured) == 1 then
      return { configured }, OBJDUMP_CANDIDATES
    end
    return nil, OBJDUMP_CANDIDATES
  end

  for _, candidate in ipairs(OBJDUMP_CANDIDATES) do
    if vim.fn.executable(candidate) == 1 then
      return { candidate }, OBJDUMP_CANDIDATES
    end
  end
  return nil, OBJDUMP_CANDIDATES
end

local function path_parts(path)
  local parts = {}
  for part in path:gmatch("[^/\\]+") do
    parts[#parts + 1] = part
  end
  return parts
end

-- Debug info stores the absolute paths from build time. Those may point at a
-- different checkout (the project moved, or the ELF was built elsewhere).
-- Look for the longest existing suffix of the recorded path under the opened
-- project's roots instead, so `/old/place/src/main.c` maps to
-- `<root>/src/main.c`.
local function relocate(path, roots)
  local parts = path_parts(path)
  for _, root in ipairs(roots) do
    for i = 1, #parts do
      local candidate = vim.fs.normalize(vim.fs.joinpath(root, table.concat(parts, "/", i)))
      if vim.uv.fs_stat(candidate) then
        return candidate
      end
    end
  end
  return nil
end

function M.make_path_resolver(elf_path)
  local roots = M.roots_for(elf_path)

  local candidate_roots = { roots.project, roots.elf_dir, vim.fn.fnamemodify(roots.elf_dir, ":h"), roots.cwd }
  local unique_roots = {}
  local seen_roots = {}
  for _, root in ipairs(candidate_roots) do
    if root and root ~= "" and not seen_roots[root] then
      seen_roots[root] = true
      unique_roots[#unique_roots + 1] = root
    end
  end

  local function resolve(raw)
    if type(raw) ~= "string" then
      return nil
    end
    raw = vim.trim(raw)
    if raw == "" then
      return nil
    end

    local normalized = vim.fs.normalize(raw)
    if vim.startswith(normalized, "/") or normalized:match("^%a:") then
      -- Prefer the copy in the opened project over the build-time path, so a
      -- stale or foreign absolute path cannot shadow the real source file.
      local relocated = relocate(normalized, unique_roots)
      if relocated then
        return relocated
      end
      if vim.uv.fs_stat(normalized) then
        return normalized
      end
      return nil
    end

    for _, root in ipairs(unique_roots) do
      local candidate = vim.fs.normalize(vim.fs.joinpath(root, raw))
      if vim.uv.fs_stat(candidate) then
        return candidate
      end
    end

    return vim.fs.normalize(vim.fs.joinpath(roots.project, raw))
  end

  return resolve
end

return M
