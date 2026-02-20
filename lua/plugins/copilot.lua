-- Configure Copilot to only show suggestions manually, and allow <Tab> to accept
-- (No auto inline/ghost suggestions while typing)

return {
  -- Ensure copilot-cmp is disabled if you only want inline (not in cmp)
  { "zbirenbaum/copilot-cmp", enabled = false },

  -- Main copilot.nvim config
  {
    "zbirenbaum/copilot.lua",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = false,             -- Don't show suggestions automatically as you type
        hide_during_completion = true,    -- Don't show Copilot suggestions when autocompletion menu is open
        keymap = {
          accept = "<Tab>",              -- Accept with Tab
          next = "<M-]>",                -- Optional: next suggestion
          prev = "<M-[>",                -- Optional: previous suggestion
          dismiss = "<C-]>",            -- Optional: dismiss suggestion
        },
      },
      panel = { enabled = false },        -- Optional: disables Copilot panel popups
    },
  },
}
