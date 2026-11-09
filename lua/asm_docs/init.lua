--- Project-wide hover and goto-definition for assembly/C symbols.
---
--- asm-lsp only knows about symbols in the current file, and our ELF
--- completion source only knows names. This module recovers a definition
--- location and the comment lines immediately above it by scanning the
--- project's source files with tree-sitter, so `K` can show JSDoc-like
--- parameter hints such as `# void delay(int cycles)`.
local M = {}

local ROOT_MARKERS = { ".git", "Makefile", "link.ld" }
local MAX_COMMENTS = 12

--- Collect contiguous comment lines immediately above `lnum` (1-based).
--- @param lines string[]
--- @param lnum integer
--- @return string[]
function M.preceding_comments(lines, lnum)
  local collected = {}
  local i = lnum - 1
  while i >= 1 do
    local line = lines[i]
    if
      line:match("^%s*#")
      or line:match("^%s*//")
      or line:match("^%s*/%*")
      or line:match("^%s*%*")
    then
      table.insert(collected, 1, vim.trim(line))
      i = i - 1
    else
      break
    end
  end
  if #collected > MAX_COMMENTS then
    local trimmed = {}
    for j = #collected - MAX_COMMENTS + 1, #collected do
      trimmed[#trimmed + 1] = collected[j]
    end
    collected = trimmed
  end
  return collected
end

local caches = {}

local function project_root(start)
  local root = vim.fs.root(start, ROOT_MARKERS)
  if not root or root == "" then
    root = vim.fn.fnamemodify(start, ":p:h")
  end
  return vim.fs.normalize(root)
end

local function source_files(root)
  local files = {}
  local seen = {}
  for _, pat in ipairs({ "**/*.s", "**/*.S", "**/*.c", "**/*.h", "**/*.ld", "**/*.lds" }) do
    for _, f in ipairs(vim.fn.globpath(root, pat, false, true)) do
      local norm = vim.fs.normalize(f)
      if not norm:match("/out/") and not seen[norm] then
        seen[norm] = true
        files[#files + 1] = norm
      end
    end
  end
  table.sort(files)
  return files
end

local function file_signature(files)
  local parts = {}
  for _, f in ipairs(files) do
    local st = vim.uv.fs_stat(f)
    parts[#parts + 1] = f .. (st and (":" .. st.mtime.sec .. ":" .. st.mtime.nsec) or ":missing")
  end
  return table.concat(parts, "\n")
end

local function function_name(fn_node, content)
  local decl = fn_node:field("declarator")[1]
  while decl do
    if decl:type() == "identifier" then
      return vim.treesitter.get_node_text(decl, content)
    end
    local next_decl = decl:field("declarator")[1]
    if next_decl then
      decl = next_decl
    else
      for child in decl:iter_children() do
        if child:type() == "identifier" then
          return vim.treesitter.get_node_text(child, content)
        end
      end
      break
    end
  end
  return nil
end

local function upsert(index, name, path, lnum, comments, defline)
  if not name or name == "" then
    return
  end
  local existing = index[name]
  if not existing or #comments > #(existing.comments or {}) then
    index[name] = {
      name = name,
      path = path,
      lnum = lnum,
      comments = comments,
      defline = defline,
    }
  end
end

local function index_file(index, path)
  local lines = vim.fn.readfile(path)
  local content = table.concat(lines, "\n")
  local ext = path:match("%.([^%.]+)$")
  local lang
  if ext == "s" or ext == "S" then
    lang = "asm"
  elseif ext == "c" or ext == "h" then
    lang = "c"
  elseif ext == "ld" or ext == "lds" then
    for i, line in ipairs(lines) do
      local name = line:match("^%s*(%.[A-Za-z_][%w%.]*)%s*:")
      if name then
        local comments = M.preceding_comments(lines, i)
        upsert(index, name, path, i, comments, vim.trim(line))
        upsert(index, name:sub(2), path, i, comments, vim.trim(line))
      end
    end
    return
  else
    return
  end

  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  if not ok_parser or not parser then
    return
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return
  end
  local root = trees[1]:root()

  if lang == "asm" then
    local ok_q, query = pcall(vim.treesitter.query.parse, "asm", "(label) @label")
    if not ok_q or not query then
      return
    end
    for _, node in query:iter_captures(root, content) do
      local text = vim.treesitter.get_node_text(node, content)
      local name = text:match("^%s*([%a_%.][%w_.$]*)%s*:")
      if name then
        local lnum = node:start() + 1
        local comments = M.preceding_comments(lines, lnum)
        upsert(index, name, path, lnum, comments, vim.trim(lines[lnum] or ""))
      end
    end
    -- `.equ` / `.set` constants are not labels but are real symbols.
    for i, line in ipairs(lines) do
      local name = line:match("^%s*%.equ%s+([%a_%.][%w_.$]*)")
        or line:match("^%s*%.set%s+([%a_%.][%w_.$]*)")
        or line:match("^%s*%.equiv%s+([%a_%.][%w_.$]*)")
        or line:match("^%s*%.eqv%s+([%a_%.][%w_.$]*)")
      if name then
        local comments = M.preceding_comments(lines, i)
        upsert(index, name, path, i, comments, vim.trim(line))
      end
    end
    -- Section declarations such as `.section .text`.
    for i, line in ipairs(lines) do
      local name = line:match("^%s*%.section%s+(%S+)")
      if name then
        name = name:gsub("[,].*", "")
        local comments = M.preceding_comments(lines, i)
        upsert(index, name, path, i, comments, vim.trim(line))
        if name:sub(1, 1) == "." then
          upsert(index, name:sub(2), path, i, comments, vim.trim(line))
        end
      end
    end
    -- Macros: `.macro name params ... .endm`.
    for i, line in ipairs(lines) do
      local name = line:match("^%s*%.macro%s+([%a_%.][%w_.$]*)")
      if name then
        local comments = M.preceding_comments(lines, i)
        upsert(index, name, path, i, comments, vim.trim(line))
      end
    end
  else
    local ok_q, query = pcall(vim.treesitter.query.parse, "c", "(function_definition) @fn")
    if not ok_q or not query then
      return
    end
    for _, node in query:iter_captures(root, content) do
      local name = function_name(node, content)
      if name and name:match("^[%a_][%w_]*$") then
        local lnum = node:start() + 1
        local comments = M.preceding_comments(lines, lnum)
        upsert(index, name, path, lnum, comments, vim.trim(lines[lnum] or ""))
      end
    end
  end
end

local function build_index(root)
  root = vim.fs.normalize(root)
  local files = source_files(root)
  local sig = file_signature(files)
  local cache = caches[root]
  if cache and cache.sig == sig and cache.index then
    return cache.index
  end
  local index = {}
  for _, f in ipairs(files) do
    index_file(index, f)
  end
  caches[root] = { sig = sig, index = index }
  return index
end

local function resolve_start(input)
  if type(input) == "string" then
    if input ~= "" then
      return input
    end
    return vim.fn.getcwd()
  end
  local name = ""
  if input then
    local ok, bufname = pcall(vim.api.nvim_buf_get_name, input)
    if ok then
      name = bufname or ""
    end
  end
  if name == "" then
    name = vim.fn.getcwd()
  end
  return name
end

local function start_path(bufnr)
  return resolve_start(bufnr)
end

--- @param name string
--- @param bufnr? integer
--- @return table|nil
function M.find_definition(name, bufnr)
  if not name or name == "" then
    return nil
  end
  local root = project_root(start_path(bufnr))
  local index = build_index(root)
  return index[name]
end

--- @param name string
--- @param bufnr? integer
--- @return string|nil
function M.hover(name, bufnr)
  if not name or name == "" then
    return nil
  end
  local def = M.find_definition(name, bufnr)
  if not def then
    return nil
  end
  local lang = def.path:match("%.c$") and "c" or "asm"
  local out = { "**" .. name .. "**", "" }
  if def.comments and #def.comments > 0 then
    for _, line in ipairs(def.comments) do
      out[#out + 1] = line
    end
    out[#out + 1] = ""
  end
  if def.defline and def.defline ~= "" then
    out[#out + 1] = "```" .. lang
    out[#out + 1] = def.defline
    out[#out + 1] = "```"
    out[#out + 1] = ""
  end
  out[#out + 1] = string.format("_%s:%d_", def.path, def.lnum)
  return table.concat(out, "\n")
end

--- @param name? string
--- @param bufnr? integer
--- @return boolean
function M.goto_definition(name, bufnr)
  if not name or name == "" then
    name = vim.fn.expand("<cword>")
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local def = M.find_definition(name, bufnr)
  if not def then
    return false
  end
  local uri = vim.uri_from_fname(def.path)
  local ok = pcall(vim.lsp.util.show_document, {
    uri = uri,
    range = {
      start = { line = def.lnum - 1, character = 0 },
      ["end"] = { line = def.lnum - 1, character = 0 },
    },
  }, "utf-8")
  if not ok then
    vim.cmd.edit(vim.fn.fnameescape(def.path))
    vim.api.nvim_win_set_cursor(0, { def.lnum, 0 })
  end
  return true
end

--- List macro definitions discovered in the project's asm files.
--- @param start string|integer|nil
--- @return table[]
function M.list_macros(start)
  local root = project_root(resolve_start(start))
  local files = source_files(root)
  local result = {}
  local seen = {}
  for _, f in ipairs(files) do
    local lines = vim.fn.readfile(f)
    for i, line in ipairs(lines) do
      local name = line:match("^%s*%.macro%s+([%a_%.][%w_.$]*)")
      if name and not seen[name] then
        seen[name] = true
        result[#result + 1] = {
          name = name,
          path = f,
          lnum = i,
          defline = vim.trim(line),
          comments = M.preceding_comments(lines, i),
        }
      end
    end
  end
  return result
end

--- Project-wide references (grep-based) for a symbol name.
--- @param name string|nil
--- @param bufnr? integer
--- @return table[]
function M.references(name, bufnr)
  if not name or name == "" then
    name = vim.fn.expand("<cword>")
  end
  if not name or name == "" then
    return {}
  end
  local root = project_root(resolve_start(bufnr or vim.api.nvim_get_current_buf()))
  local files = source_files(root)
  local escaped = vim.pesc(name)
  local pat = "%f[%w_.$]" .. escaped .. "%f[^%w_.$]"
  local results = {}
  for _, f in ipairs(files) do
    local lines = vim.fn.readfile(f)
    for i, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      local is_comment = trimmed:match("^#")
        or trimmed:match("^//")
        or trimmed:match("^/%*")
        or trimmed:match("^%*")
      if not is_comment and line:match(pat) then
        results[#results + 1] = {
          filename = f,
          lnum = i,
          col = (line:find(escaped, 1, true) or 1),
          text = vim.trim(line),
        }
      end
    end
  end
  return results
end

return M