local M = {}

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.define_highlight(config)
  vim.api.nvim_set_hl(0, "DisasmMatch", { default = true, link = (config and config.highlight) or "Visual" })
end

function M.open(state)
  if win_valid(state.asm_win) then
    return true
  end
  if not win_valid(state.source_win) then
    state.source_win = vim.api.nvim_get_current_win()
  end

  local previous = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(state.source_win)
  vim.cmd("rightbelow vsplit")
  state.asm_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(previous)
  return true
end

function M.ensure_buffer(state)
  if buf_valid(state.asm_buf) then
    return state.asm_buf
  end
  state.asm_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.asm_buf, "Disassembly")
  vim.bo[state.asm_buf].buftype = "nofile"
  vim.bo[state.asm_buf].bufhidden = "wipe"
  vim.bo[state.asm_buf].swapfile = false
  vim.bo[state.asm_buf].buflisted = false
  return state.asm_buf
end

function M.set_winbar(state)
  if not win_valid(state.asm_win) then
    return
  end
  if not (state.config and state.config.winbar) then
    vim.wo[state.asm_win].winbar = ""
    return
  end
  local name = state.elf and vim.fn.fnamemodify(state.elf, ":~:.") or "disassembly"
  local modified = false
  if win_valid(state.source_win) then
    modified = vim.bo[vim.api.nvim_win_get_buf(state.source_win)].modified
  end
  local suffix = modified and " [modified]" or ""
  vim.wo[state.asm_win].winbar = " Disassembly: " .. name .. suffix
end

function M.set_keymaps(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  local buf = state.asm_buf
  local base = { buffer = buf, silent = true }
  vim.keymap.set("n", "q", function()
    require("disasm").close()
  end, vim.tbl_extend("force", base, { desc = "Close disassembly" }))
  vim.keymap.set("n", "r", function()
    require("disasm").refresh()
  end, vim.tbl_extend("force", base, { desc = "Refresh disassembly" }))
  vim.keymap.set("n", "K", function()
    require("riscv_asm").hover_current()
  end, vim.tbl_extend("force", base, { desc = "Hover (RISC-V)" }))
end

function M.render(state)
  if not M.open(state) then
    return false
  end
  local buf = M.ensure_buffer(state)

  vim.api.nvim_win_set_buf(state.asm_win, buf)

  vim.wo[state.asm_win].number = true
  vim.wo[state.asm_win].relativenumber = false
  vim.wo[state.asm_win].signcolumn = "no"
  vim.wo[state.asm_win].foldcolumn = "0"
  vim.wo[state.asm_win].cursorline = true
  vim.wo[state.asm_win].wrap = false

  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.lines or {})
  vim.bo[buf].filetype = "asm"
  pcall(vim.treesitter.start, buf, "asm")
  pcall(vim.diagnostic.enable, false, { bufnr = buf })
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  M.set_winbar(state)
  M.set_keymaps(state)
  return true
end

function M.clear(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.asm_buf, state.ns, 0, -1)
end

function M.highlight(state, ranges)
  M.clear(state)
  if not buf_valid(state.asm_buf) then
    return
  end
  for _, range in ipairs(ranges or {}) do
    for row = range[1], range[2] do
      vim.api.nvim_buf_set_extmark(state.asm_buf, state.ns, row - 1, 0, {
        line_hl_group = "DisasmMatch",
        priority = 200,
      })
    end
  end
end

function M.scroll_to(state, row)
  if not win_valid(state.asm_win) then
    return
  end
  vim.api.nvim_win_set_cursor(state.asm_win, { row, 0 })
  vim.api.nvim_win_call(state.asm_win, function()
    vim.cmd("normal! zz")
  end)
end

function M.close(state)
  if win_valid(state.asm_win) then
    vim.api.nvim_win_close(state.asm_win, true)
  end
  state.asm_win = nil
  state.asm_buf = nil
end

return M
