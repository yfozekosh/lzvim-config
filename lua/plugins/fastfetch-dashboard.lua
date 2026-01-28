local function get_fastfetch(isLogo)
  isLogo = isLogo or false
  local shCommand = "fastfetch --pipe --disable-linewrap --no-buffer" .. (isLogo and "" or " --logo-type none")
  local handle = io.popen(shCommand)
  if not handle then
    return "fastfetch not available"
  end

  local result = handle:read("*a")
  handle:close()
  if not result then
    return "fastfetch failed"
  end

  -- More aggressive cleanup
  result = result:gsub("\27%[[%d;]*[ABCDEFGHJKSTfmnsulh]", "") -- Remove all ANSI sequences
  result = result:gsub("[\128-\255]", "") -- Remove all non-ASCII characters

  local maxWidth = 51
  local cropped_lines = {}
  local i = 0
  for line in result:gmatch("[^\n]+") do
    i = i + 1
    if #line > maxWidth then
      line = line:sub(1, maxWidth)
    end
    if #line < maxWidth then
      -- Add spaces at the end.
      line = line .. string.rep(" ", maxWidth - #line)
    end
    if i == 1 then
      line = "  ! Welcome back to NEOVIM !"
    end
    if i == 2 then
      line = ""
    end
    if line:find("^Disk") == nil and line:find("^Batter") == nil then
      if i > 2 and i < 24 then
        line = "   █  " .. line .. "  █"
      end
      table.insert(cropped_lines, line)
    end
  end

  result = table.concat(cropped_lines, "\n")

  return result
end

return {
  "snacks.nvim",
  opts = {
    dashboard = {
      preset = {
        pick = function(cmd, opts)
          return LazyVim.pick(cmd, opts)()
        end,
        --- GET fastfetch output
        header = get_fastfetch(),
        ---@type snacks.dashboard.Item[]
        keys = {
          { icon = "", key = "w", desc = "Open Last File", action = ":LastFile" },
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
          },
          { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
    },
  },
}
