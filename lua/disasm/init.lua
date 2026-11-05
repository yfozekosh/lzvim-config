local config_mod = require("disasm.config")
local parser = require("disasm.parser")
local view = require("disasm.view")

local M = {}

local state = {
  config = config_mod.setup({}),
  ns = nil,
  asm_buf = nil,
  asm_win = nil,
  source_win = nil,
  elf = nil,
  lines = {},
  index = {},
  has_markers = false,
  augroup = nil,
  warned_modified = {},
  warned_stale = false,
  elf_mtime = nil,
  elf_timer = nil,
  elf_changed_notified = false,
  refreshing = false,
}

function M.setup(opts)
  state.config = config_mod.setup(opts)
  state.ns = vim.api.nvim_create_namespace("disasm.highlight")
  view.define_highlight(state.config)

  if not state.augroup then
    state.augroup = vim.api.nvim_create_augroup("Disasm", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "WinEnter" }, {
      group = state.augroup,
      callback = function()
        if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
          M.update_highlight()
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = state.augroup,
      callback = function(ev)
        if state.asm_buf and ev.buf == state.asm_buf then
          M.stop_elf_watch()
          state.asm_buf = nil
          state.asm_win = nil
          state.lines = {}
          state.index = {}
          state.elf = nil
          state.has_markers = false
        end
      end,
    })
  end
  state.warned_modified = {}
  state.warned_stale = false
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Disasm" })
end

local function elf_mtime_key(elf)
  local st = vim.uv.fs_stat(elf)
  if not st then
    return nil
  end
  return tostring(st.mtime.sec) .. ":" .. tostring(st.mtime.nsec)
end

function M.stop_elf_watch()
  if state.elf_timer then
    pcall(function()
      state.elf_timer:stop()
      state.elf_timer:close()
    end)
    state.elf_timer = nil
  end
end

function M.start_elf_watch()
  M.stop_elf_watch()
  local timer = vim.uv.new_timer()
  state.elf_timer = timer
  timer:start(1000, 1000, function()
    vim.schedule(function()
      if state.refreshing then
        return
      end
      if not (state.elf and state.asm_win and vim.api.nvim_win_is_valid(state.asm_win)) then
        return
      end
      local new_key = elf_mtime_key(state.elf)
      if not new_key then
        return
      end
      if state.elf_mtime == nil then
        state.elf_mtime = new_key
        return
      end
      if new_key == state.elf_mtime then
        return
      end
      state.elf_mtime = new_key
      vim.schedule(function()
        if state.refreshing then
          return
        end
        state.refreshing = true
        if state.config.auto_refresh ~= false then
          notify("ELF changed; refreshing disassembly.", vim.log.levels.INFO)
          M.refresh()
        else
          if not state.elf_changed_notified then
            state.elf_changed_notified = true
            notify("ELF changed; run :DisasmRefresh to update.", vim.log.levels.WARN)
          end
        end
        state.refreshing = false
      end)
    end)
  end)
end

function M.open(elf_arg)
  if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
    M.refresh(elf_arg)
    return
  end

  if not (state.source_win and vim.api.nvim_win_is_valid(state.source_win)) then
    state.source_win = vim.api.nvim_get_current_win()
  end
  local current = vim.api.nvim_get_current_win()
  if current ~= state.asm_win then
    state.source_win = current
  end

  local source_buf = vim.api.nvim_win_get_buf(state.source_win)
  local start_path = vim.api.nvim_buf_get_name(source_buf)
  if start_path == "" then
    start_path = vim.fn.getcwd()
  end

  local elf = elf_arg
  if not elf or elf == "" then
    local candidates = config_mod.find_elf(state.config, start_path)
    if #candidates == 0 then
      notify("No ELF found. Build first or pass a path: :DisasmOpen /path/to.elf", vim.log.levels.ERROR)
      return
    end
    if #candidates > 1 then
      vim.ui.select(candidates, { prompt = "Select ELF to disassemble:" }, function(choice)
        if choice then
          M.open_with(choice)
        end
      end)
      return
    end
    elf = candidates[1]
  end

  M.open_with(vim.fs.normalize(elf))
end

function M.open_with(elf)
  state.refreshing = true
  local objdump_argv, candidates = config_mod.resolve_objdump(state.config)
  if not objdump_argv then
    state.refreshing = false
    notify("objdump not found. Tried: " .. table.concat(candidates, ", ") .. "\nSet vim.g.disasm.objdump", vim.log.levels.ERROR)
    return
  end

  local argv = vim.list_extend(vim.list_extend({}, objdump_argv), state.config.args or {})
  table.insert(argv, elf)

  local result = vim.system(argv, { text = true }):wait()
  if result.code ~= 0 then
    state.refreshing = false
    notify("objdump failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local output = vim.split(result.stdout or "", "\n", { plain = true })
  if #output > 0 and output[#output] == "" then
    table.remove(output)
  end

  local resolver = config_mod.make_path_resolver(elf)
  local parsed = parser.parse(output, { resolve_path = resolver })

  state.elf = elf
  state.lines = parsed.lines
  state.index = parsed.index
  state.has_markers = parsed.has_markers
  state.warned_modified = {}
  state.warned_stale = false
  state.elf_changed_notified = false
  state.elf_mtime = elf_mtime_key(elf)

  if not view.open(state) then
    state.refreshing = false
    return
  end
  if not view.render(state) then
    state.refreshing = false
    return
  end

  if not parsed.has_markers then
    notify("ELF has no debug line info; showing disassembly without line mapping.", vim.log.levels.WARN)
  end

  M.stop_elf_watch()
  M.start_elf_watch()
  M.check_stale()
  M.update_highlight()
  state.refreshing = false
end

function M.refresh(elf_arg)
  if elf_arg and elf_arg ~= "" then
    M.open(elf_arg)
    return
  end
  if not state.elf then
    notify("Nothing to refresh.", vim.log.levels.WARN)
    return
  end
  M.open_with(state.elf)
end

function M.toggle(elf_arg)
  if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
    M.close()
  else
    M.open(elf_arg)
  end
end

function M.close()
  M.stop_elf_watch()
  view.close(state)
  state.asm_buf = nil
  state.asm_win = nil
  state.lines = {}
  state.index = {}
  state.elf = nil
  state.has_markers = false
  state.warned_modified = {}
  state.warned_stale = false
  state.elf_mtime = nil
  state.elf_changed_notified = false
  state.refreshing = false
end

function M.check_stale()
  if state.warned_stale then
    return
  end
  if not state.elf then
    return
  end
  local elf_stat = vim.uv.fs_stat(state.elf)
  if not elf_stat then
    return
  end
  local elf_mtime = elf_stat.mtime.sec

  local stale = {}
  for path in pairs(state.index) do
    local st = vim.uv.fs_stat(path)
    if st and st.mtime.sec > elf_mtime then
      stale[#stale + 1] = path
    end
  end

  if #stale > 0 then
    state.warned_stale = true
    local names = {}
    for i = 1, math.min(#stale, 3) do
      names[#names + 1] = vim.fn.fnamemodify(stale[i], ":t")
    end
    local more = #stale > 3 and (" (+" .. (#stale - 3) .. " more)") or ""
    notify("Source newer than ELF; rebuild for accurate mapping: " .. table.concat(names, ", ") .. more, vim.log.levels.WARN)
  end
end

function M.update_highlight()
  if not (state.source_win and vim.api.nvim_win_is_valid(state.source_win)) then
    return
  end
  if not (state.asm_win and vim.api.nvim_win_is_valid(state.asm_win)) then
    return
  end
  if not (state.asm_buf and vim.api.nvim_buf_is_valid(state.asm_buf)) then
    return
  end
  if vim.api.nvim_get_current_win() ~= state.source_win then
    return
  end

  local buf = vim.api.nvim_win_get_buf(state.source_win)
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local line = vim.api.nvim_win_get_cursor(state.source_win)[1]

  view.clear(state)
  view.set_winbar(state)

  local entry = state.index[path] and state.index[path][line]
  if not entry then
    return
  end

  view.highlight(state, entry.ranges)
  if state.config.auto_scroll then
    view.scroll_to(state, entry.first_row)
  end

  if vim.bo[buf].modified and not state.warned_modified[buf] then
    state.warned_modified[buf] = true
    notify("Source buffer modified; line mapping may be off.", vim.log.levels.WARN)
  end
end

return M
