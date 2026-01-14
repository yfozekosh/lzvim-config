vim.keymap.set("n", "<leader><S-b>", function()
  -- Open terminal in split and run dotnet build
  vim.cmd("split")
  vim.cmd("terminal dotnet build ./src")

  -- Get terminal buffer and job id
  local term_buf = vim.api.nvim_get_current_buf()
  local term_job_id = vim.b.terminal_job_id

  -- Set up job watcher
  -- vim.fn.jobwait({ term_job_id }, -1) -- Wait for job to finish
  -- vim.schedule(function()
    -- vim.cmd("Trouble diagnostics")
  -- end)

  -- vim.cmd("startinsert") -- Enter terminal input mode
end, { desc = "Run dotnet build and show diagnostics", noremap = true, silent = true })
