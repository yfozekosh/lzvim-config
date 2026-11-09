-- <leader>cb : build the current project with `make` and show its output
-- in a floating window.
local M = {}

local function run(target)
  target = target or nil
  local is_clean = target == "clean"
  local title = is_clean and " Clean (make clean) " or " Build (make) "
  local notify_title = is_clean and "Clean" or "Build"
  local cmd = { "make" }
  if target then
    table.insert(cmd, target)
  end

  if vim.fn.executable("make") == 0 then
    vim.notify("`make` not found on PATH", vim.log.levels.ERROR, { title = notify_title })
    return
  end

  local cwd = vim.fn.getcwd()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  local width = math.max(40, math.floor(vim.o.columns * 0.8))
  local height = math.max(10, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  -- A terminal buffer interprets the ANSI colours, carriage returns, etc.
  -- that build tools emit, instead of showing raw escape sequences.
  local chan = vim.api.nvim_open_term(buf, {})
  local function send(text)
    if text and text ~= "" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_chan_send(chan, text)
        end
      end)
    end
  end

  local label = is_clean and "Clean: make clean" or "Build: make"
  send(label .. "\r\ncwd: " .. cwd .. "\r\n" .. string.rep("=", 80) .. "\r\n")

  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set({ "n", "t" }, "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "t" }, "<Esc>", close, { buffer = buf, nowait = true, silent = true })
  vim.cmd("stopinsert")

  vim.system(cmd, {
    cwd = cwd,
    text = true,
    stdout = function(_, data)
      send(data)
    end,
    stderr = function(_, data)
      send(data)
    end,
  }, function(res)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        send("\r\n" .. string.rep("=", 40) .. "\r\nexit code: " .. tostring(res.code) .. "\r\n")
      end
      if res.code == 0 then
        vim.notify(is_clean and "Clean succeeded" or "Build succeeded", vim.log.levels.INFO, { title = notify_title })
      else
        vim.notify((is_clean and "Clean" or "Build") .. " failed (exit " .. tostring(res.code) .. ")", vim.log.levels.ERROR, { title = notify_title })
      end
    end)
  end)
end

M.run = run

vim.api.nvim_create_user_command("Build", function(opts)
  run(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Build with make and show output in a floating window" })

vim.api.nvim_create_user_command("Clean", function()
  run("clean")
end, { desc = "Clean with make clean and show output in a floating window" })

return M