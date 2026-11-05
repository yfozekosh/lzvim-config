--- Pure parser for `objdump -d -l` output.
---
--- It does not touch buffers or the filesystem. Callers pass a
--- `resolve_path` callback so relative debug paths can be made absolute
--- before they become index keys.
local M = {}

local function looks_like_path(path)
  return path:match("^/") ~= nil
    or path:match("^%a:[/\\]") ~= nil
    or path:find("[/\\]") ~= nil
end

local function parse_source_marker(line)
  local path, line_number = line:match("^%s*(.-):(%d+)")
  if not path or not line_number or not looks_like_path(path) then
    return nil
  end
  return path, tonumber(line_number)
end

local function parse_instruction(line)
  local address = line:match("^%s*([0-9a-fA-F]+):%s+")
  return address ~= nil
end

local function is_function_or_section_header(line)
  return line:match("^%x+ <.+>:$") ~= nil
    or line:match("^%S+%(%):$") ~= nil
    or line:match("^Disassembly of section") ~= nil
    or line:match("^Contents of section") ~= nil
end

--- @param asm_lines string[]
--- @param opts { resolve_path: fun(raw: string): string? }
--- @return { lines: string[], index: table<string, table<integer, table>>, has_markers: boolean }
function M.parse(asm_lines, opts)
  opts = opts or {}
  local resolve_path = opts.resolve_path or vim.fs.normalize

  local lines = {}
  local index = {}
  local has_markers = false
  local current

  local function append(line)
    lines[#lines + 1] = line
    return #lines
  end

  local function add_instruction(row, path, line_number)
    local by_file = index[path]
    if not by_file then
      by_file = {}
      index[path] = by_file
    end

    local entry = by_file[line_number]
    if not entry then
      entry = { first_row = row, ranges = {} }
      by_file[line_number] = entry
    end

    local range = current.range
    if range and range[2] + 1 == row then
      range[2] = row
    else
      range = { row, row }
      entry.ranges[#entry.ranges + 1] = range
      current.range = range
    end
  end

  for _, line in ipairs(asm_lines) do
    local marker_path, marker_line = parse_source_marker(line)
    if marker_path then
      has_markers = true
      current = { path = resolve_path(marker_path) or marker_path, line = marker_line }
    elseif parse_instruction(line) then
      local row = append(line)
      if current then
        add_instruction(row, current.path, current.line)
      end
    elseif is_function_or_section_header(line) then
      append(line)
      current = nil
    else
      append(line)
    end
  end

  return {
    lines = lines,
    index = index,
    has_markers = has_markers,
  }
end

return M
