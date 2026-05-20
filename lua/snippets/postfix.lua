-- LuaSnip postfix snippets for C# and TypeScript
-- Place in: ~/.config/nvim/lua/snippets/postfix.lua

local ls = require("luasnip")
local postfix = require("luasnip.extras.postfix").postfix
local s = ls.snippet
local i = ls.insert_node
local f = ls.function_node

local function expr_var(_, parent)
  local matched = parent.snippet.env.POSTFIX_MATCH
  if not matched or matched == "" then
    matched = "expr"
  end
  return "var " .. i(1, "variable") .. " = " .. matched .. ";"
end

ls.add_snippets("csharp", {
  postfix(".var", f(function(_, parent)
    local matched = parent.snippet.env.POSTFIX_MATCH
    return "var " .. "${1:variable}" .. " = " .. matched .. ";"
  end, {})),
})

ls.add_snippets("typescript", {
  postfix(".var", f(function(_, parent)
    local matched = parent.snippet.env.POSTFIX_MATCH
    return "const " .. "${1:variable}" .. " = " .. matched .. ";"
  end, {})),
})

-- Extend for more filetypes as needed
