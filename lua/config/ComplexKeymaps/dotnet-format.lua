vim.keymap.set("n", "<leader>kl", function()
  local job_id = vim.fn.jobstart({ "csharpier", "format", "." }, {
    -- term = true, -- IMPORTANT: makes it a terminal job
    stdout_buffered = true,
    sterr_buffered = true,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          vim.notify("CSharpier formatting completed ✅", vim.log.levels.INFO)
        else
          vim.notify("CSharpier formatting failed ❌", vim.log.levels.ERROR)
        end
      end)
    end,
  })
  vim.notify("Started csharpier format job (ID: " .. job_id .. ")", vim.log.levels.INFO)

end, { desc = "Run csharpier format", noremap = true, silent = true })
