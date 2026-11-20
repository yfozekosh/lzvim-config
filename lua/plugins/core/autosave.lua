return {
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged" },
  opts = {
    enabled = true,
    trigger_events = {
      -- Plugin default, kept explicit.
      immediate_save = { "BufLeave", "FocusLost", "QuitPre", "VimSuspend" },
      -- Default also has TextChanged, which saves after every normal-mode
      -- edit (and runs BufWritePost linters each time). Normal-mode edits
      -- are still saved on BufLeave/FocusLost/quit.
      defer_save = { "InsertLeave" },
      cancel_deferred_save = { "InsertEnter" },
    },
    -- Only real, already-existing files (no scratch/unnamed/special buffers).
    -- The plugin itself only checks 'modifiable'.
    condition = function(buf)
      if vim.bo[buf].buftype ~= "" then
        return false
      end
      local name = vim.api.nvim_buf_get_name(buf)
      return name ~= "" and vim.fn.filereadable(name) == 1
    end,
    write_all_buffers = false,
    debounce_delay = 5000,
  },
}
