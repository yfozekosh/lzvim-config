-- Configure Copilot to only show suggestions manually, and allow <Tab> to accept
-- (No auto inline/ghost suggestions while typing)

return {
  -- Main copilot.nvim config
  {
    "zbirenbaum/copilot.lua",
    -- Starting Copilot at launch costs ~100ms and spawns a language server
    -- before it can possibly be used. Suggestions are manual-only, so load it
    -- the first time insert mode is entered.
    event = "InsertEnter",
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
