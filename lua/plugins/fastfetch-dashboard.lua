local function get_fastfetch()
  local handle = io.popen("fastfetch --logo-type small --pipe")
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
  -- result = result:gsub("[\1-\31]", "") -- Remove control characters except newline/tab
  -- result = result:gsub("%s+$", "") -- Remove trailing whitespace

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
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
          },
          { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
    },
  },
}
