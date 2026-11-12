local M = {}

local function excluded(path)
  return path:match("(^|/)%.git/") ~= nil
end

function M.list_files()
  local seen = {}
  local files = {}
  for _, path in ipairs(vim.fn.glob("**/*", false, true)) do
    if vim.fn.isdirectory(path) == 0 and not excluded(path) and not seen[path] then
      seen[path] = true
      files[#files + 1] = path
    end
  end
  table.sort(files)
  while #files > 5000 do
    table.remove(files)
  end
  return files
end

local function find_files()
  local files = M.list_files()
  if #files == 0 then
    vim.notify("No files found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(files, { prompt = "Find file", kind = "file" }, function(choice)
    if choice then
      vim.cmd.edit(vim.fn.fnameescape(choice))
    end
  end)
end

function M.grep_command(pattern)
  return "grep! " .. vim.fn.shellescape(pattern, 1)
end

local function grep()
  vim.ui.input({ prompt = "Grep: " }, function(input)
    if not input or input == "" then
      return
    end
    vim.cmd(M.grep_command(input))
    vim.cmd("copen")
  end)
end

function M.setup()
  vim.keymap.set("n", "<leader><space>", find_files, { desc = "Find file" })
  vim.keymap.set("n", "<leader>/", grep, { desc = "Grep" })
  vim.keymap.set("n", "<leader>e", "<cmd>Lexplore<cr>", { desc = "Explorer" })
  if vim.fn.executable("lazygit") == 1 then
    vim.keymap.set("n", "<leader>gg", function()
      vim.cmd("terminal lazygit")
    end, { desc = "Lazygit" })
  end
end

return M
