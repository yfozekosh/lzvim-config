local M = {}

local bg = "#2E3440"
local bg_alt = "#3B4252"
local bg_sel = "#434C5E"
local fg = "#D8DEE9"
local fg_bright = "#ECEFF4"
local comment = "#616E88"
local frost = "#88C0D0"
local frost2 = "#81A1C1"
local frost3 = "#8FBCBB"
local blue = "#5E81AC"
local red = "#BF616A"
local yellow = "#EBCB8B"
local green = "#A3BE8C"
local purple = "#B48EAD"

local function set(name, opts)
  vim.api.nvim_set_hl(0, name, opts)
end

local function set_each(names, opts)
  for _, name in ipairs(names) do
    set(name, opts)
  end
end

function M.setup()
  vim.o.background = "dark"
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end

  set_each({ "Normal", "NormalNC" }, { fg = fg, bg = bg })
  set("NormalFloat", { fg = fg, bg = bg_alt })
  set("FloatBorder", { fg = frost2, bg = bg_alt })

  set_each({ "Comment", "SpecialComment" }, { fg = comment, italic = true })
  set_each({ "Constant", "Number", "Boolean", "Float", "Character" }, { fg = purple })
  set("String", { fg = green })
  set_each({ "Identifier", "Function" }, { fg = frost })
  set_each({
    "Statement",
    "Keyword",
    "Conditional",
    "Repeat",
    "Label",
    "Operator",
  }, { fg = frost2 })
  set_each({ "PreProc", "Include", "Define", "Macro", "PreCondit" }, { fg = frost2 })
  set_each({ "Type", "StorageClass", "Structure", "Typedef" }, { fg = frost3 })
  set_each({ "Special", "SpecialChar", "Delimiter", "Tag" }, { fg = frost })

  set_each({ "Error", "ErrorMsg", "DiagnosticError" }, { fg = red })
  set("Todo", { fg = yellow, bg = bg_alt, bold = true })
  set_each({ "WarningMsg", "DiagnosticWarn" }, { fg = yellow })
  set_each({ "ModeMsg", "MoreMsg", "Question", "Title", "Directory" }, { fg = frost })

  set_each({ "Visual", "VisualNOS", "PmenuSel" }, { bg = bg_sel })
  set_each({ "Search", "IncSearch", "CurSearch" }, { fg = fg_bright, bg = blue, bold = true })
  set("MatchParen", { fg = frost, bold = true, underline = true })
  set_each({ "CursorLine", "ColorColumn" }, { bg = bg_alt })
  set("CursorLineNr", { fg = yellow, bold = true })
  set_each({
    "LineNr",
    "FoldColumn",
    "NonText",
    "Whitespace",
    "SpecialKey",
    "EndOfBuffer",
  }, { fg = comment })
  set("SignColumn", { fg = fg, bg = bg })
  set_each({ "StatusLine", "StatusLineNC", "WinSeparator", "VertSplit" }, { fg = fg, bg = bg_alt })
  set("StatusLineMode", { fg = bg, bg = frost, bold = true })
  set_each({ "Pmenu", "PmenuSbar" }, { fg = fg, bg = bg_alt })
  set("PmenuThumb", { bg = bg_sel })
  set("Folded", { fg = frost2, bg = bg_alt })

  set("DiffAdd", { fg = green, bg = bg_alt })
  set("DiffChange", { fg = yellow, bg = bg_alt })
  set("DiffDelete", { fg = red, bg = bg_alt })
  set("DiffText", { fg = fg_bright, bg = blue })

  set("DiagnosticInfo", { fg = frost })
  set("DiagnosticHint", { fg = frost3 })
  set("DiagnosticVirtualTextError", { fg = red, italic = true })
  set("DiagnosticVirtualTextWarn", { fg = yellow, italic = true })
  set("DiagnosticVirtualTextInfo", { fg = frost, italic = true })
  set("DiagnosticVirtualTextHint", { fg = frost3, italic = true })
  set("DiagnosticUnderlineError", { fg = red, underline = true })
  set("DiagnosticUnderlineWarn", { fg = yellow, underline = true })
  set("DiagnosticUnderlineInfo", { fg = frost, underline = true })
  set("DiagnosticUnderlineHint", { fg = frost3, underline = true })
  set("LspInlayHint", { fg = comment, italic = true })
  set("QuickFixLine", { bg = bg_sel, bold = true })
end

return M
