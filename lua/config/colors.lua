-- lua/config/extmarks.lua
-- Extmark inspector with buffer text context, highlight color info, and "q" to close.
-- Provides:
--   :InspectExtmarks [line|cursor|buffer]
--   :lua InspectExtmarks({ scope = "line" })
-- Optional mapping: <leader>ue

local function hl_to_hex(n)
  if type(n) ~= "number" then
    return nil
  end
  return string.format("#%06x", n)
end

local function describe_hl(name)
  if not name or name == "" then
    return nil
  end

  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = true })
  if not ok or not hl then
    return nil
  end

  local fg = hl_to_hex(hl.fg)
  local bg = hl_to_hex(hl.bg)
  local sp = hl_to_hex(hl.sp)
  local link = hl.link

  local bits = {}
  if link then
    table.insert(bits, "link=" .. link)
  end
  if fg then
    table.insert(bits, "fg=" .. fg)
  end
  if bg then
    table.insert(bits, "bg=" .. bg)
  end
  if sp then
    table.insert(bits, "sp=" .. sp)
  end

  if hl.bold then
    table.insert(bits, "bold")
  end
  if hl.italic then
    table.insert(bits, "italic")
  end
  if hl.underline then
    table.insert(bits, "underline")
  end
  if hl.undercurl then
    table.insert(bits, "undercurl")
  end
  if hl.strikethrough then
    table.insert(bits, "strike")
  end
  if hl.reverse then
    table.insert(bits, "reverse")
  end
  if hl.blend ~= nil then
    table.insert(bits, "blend=" .. tostring(hl.blend))
  end

  return table.concat(bits, " ")
end

_G.InspectExtmarks = function(opts)
  opts = opts or {}

  local bufnr = 0
  local scope = opts.scope or "line" -- "line" | "cursor" | "buffer"
  local max = opts.max or 200

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local from, to
  if scope == "cursor" then
    from, to = { row, col }, { row, col + 1 }
  elseif scope == "buffer" then
    from, to = { 0, 0 }, { -1, -1 }
  else -- line
    from, to = { row, 0 }, { row, -1 }
  end

  local namespaces = vim.api.nvim_get_namespaces()
  local results = {}

  for ns_name, ns_id in pairs(namespaces) do
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, from, to, { details = true })
    for _, m in ipairs(marks) do
      local id, mrow, mcol, details = m[1], m[2], m[3], m[4] or {}
      results[#results + 1] = {
        ns = ns_name,
        ns_id = ns_id,
        id = id,
        row = mrow,
        col = mcol,
        opts = details,
      }
    end
  end

  table.sort(results, function(a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    if a.col ~= b.col then
      return a.col < b.col
    end
    return a.ns < b.ns
  end)

  if #results > max then
    results = { unpack(results, 1, max) }
  end

  local lines = {}
  lines[#lines + 1] = string.format(
    "Extmarks (buf=%d, scope=%s, showing=%d)  -- :InspectExtmarks [line|cursor|buffer]",
    vim.api.nvim_get_current_buf(),
    scope,
    #results
  )
  lines[#lines + 1] = string.rep("=", 100)

  for _, r in ipairs(results) do
    local bufline = vim.api.nvim_buf_get_lines(bufnr, r.row, r.row + 1, false)[1] or ""
    local caret = string.rep(" ", r.col) .. "^"

    lines[#lines + 1] = string.format("row=%d col=%d  ns=%s  id=%d  ns_id=%d", r.row, r.col, r.ns, r.id, r.ns_id)
    lines[#lines + 1] = "  " .. bufline
    lines[#lines + 1] = "  " .. caret

    local o = r.opts or {}

    -- Show key extmark options first
    local interesting = {
      hl_group = o.hl_group,
      hl_group_link = o.hl_group_link,
      priority = o.priority,
      virt_text_pos = o.virt_text_pos,
      virt_text = o.virt_text,
      virt_lines = o.virt_lines,
      sign_text = o.sign_text,
      conceal = o.conceal,
      end_row = o.end_row,
      end_col = o.end_col,
    }

    for k, v in pairs(interesting) do
      if v ~= nil then
        lines[#lines + 1] = string.format("  %-16s %s", k .. ":", vim.inspect(v):gsub("\n", " "))
      end
    end

    -- Collect highlight groups used by this extmark (incl. virt_text chunks)
    local hl_names = {}
    if o.hl_group then
      table.insert(hl_names, o.hl_group)
    end
    if o.hl_group_link then
      table.insert(hl_names, o.hl_group_link)
    end
    if o.virt_text then
      for _, chunk in ipairs(o.virt_text) do
        local hlname = chunk[2]
        if type(hlname) == "string" and hlname ~= "" then
          table.insert(hl_names, hlname)
        end
      end
    end

    local seen = {}
    for _, name in ipairs(hl_names) do
      if not seen[name] then
        seen[name] = true
        local desc = describe_hl(name)
        if desc then
          lines[#lines + 1] = string.format("  hl %-14s %s", name .. ":", desc)
        end
      end
    end

    lines[#lines + 1] = string.rep("-", 100)
  end

  local out = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(out, "Extmarks://inspect")
  vim.bo[out].buftype = "nofile"
  vim.bo[out].bufhidden = "wipe"
  vim.bo[out].swapfile = false
  vim.bo[out].modifiable = true
  vim.bo[out].buflisted = false
  vim.bo[out].filetype = "lua"

  vim.api.nvim_buf_set_lines(out, 0, -1, false, lines)
  vim.bo[out].modifiable = false

  -- q closes this window
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = out, silent = true, nowait = true })

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, out)
end

-- User command wrapper:
vim.api.nvim_create_user_command("InspectExtmarks", function(cmd)
  local arg = (cmd.args or ""):lower()
  if arg == "line" or arg == "" then
    _G.InspectExtmarks({ scope = "line" })
  elseif arg == "cursor" then
    _G.InspectExtmarks({ scope = "cursor" })
  elseif arg == "buffer" then
    _G.InspectExtmarks({ scope = "buffer" })
  else
    _G.InspectExtmarks({ scope = "line" })
  end
end, { nargs = "?" })

-- Optional mapping:
vim.keymap.set("n", "<leader>ue", function()
  _G.InspectExtmarks({ scope = "line" })
end, { desc = "Inspect extmarks (line)" })

-- Highlight overrides (apply after colorscheme to avoid being overwritten)
-- vim.api.nvim_create_autocmd("ColorScheme"c> {
-- callback = function()
--   -- Snacks Picker
--
--   -- Option B (uncomment) for full control:
--   -- vim.api.nvim_set_hl(0, "MyInlayHint", { fg = "#88C0D0", italic = true })
--   -- vim.api.nvim_set_hl(0, "LspInlayHint", { link = "MyInlayHint" })
-- end,
-- })

vim.api.nvim_set_hl(0, "SnacksPickerDir", { link = "Directory" })
vim.api.nvim_set_hl(0, "SnacksPickerPathHidden", { link = "NonText" })
vim.api.nvim_set_hl(0, "SnacksPickerGitStatusUntracked", { link = "DiagnosticInfo" })

-- Inlay hints: avoid "Special" (often looks white in Nord). Use a diagnostic group or your own.
-- Option A: link to a themed group
vim.api.nvim_set_hl(0, "MyInlayHint", { fg = "#566C8A", italic = true })
vim.api.nvim_set_hl(0, "LspInlayHint", { link = "MyInlayHint" })
