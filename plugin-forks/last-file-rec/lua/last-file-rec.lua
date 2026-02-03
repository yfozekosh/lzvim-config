local M = {}

function M.setup()
  local api = vim.api
  local fn = vim.fn
  local Path = require("plenary.path")

  local cache_path = Path:new(fn.stdpath("cache"), "last_file.txt")

  local function is_real_file(bufnr)
    if not api.nvim_buf_is_loaded(bufnr) then
      return false
    end

    local name = api.nvim_buf_get_name(bufnr)
    if name == "" then
      return false
    end

    -- ignore buffers like term://, oil://, etc.
    if name:match("^[a-zA-Z]+://") then
      return false
    end

    return fn.filereadable(name) == 1
  end

  local function write_last_file(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if not is_real_file(bufnr) then
      return
    end

    cache_path:parent():mkdir({ parents = true })
    cache_path:write(api.nvim_buf_get_name(bufnr) .. "\n", "w")
  end

  local group = api.nvim_create_augroup("LastFileCache", { clear = true })

  local last_checked_cwd = nil
  local frontend_indicators = { "package.json", "node_modules", "index.html" }
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(args)
      write_last_file(args.buf)
      local cwd = vim.fn.getcwd()
      if last_checked_cwd == cwd then
        return
      end
      last_checked_cwd = cwd
      for _, file in ipairs(frontend_indicators) do
        if vim.fn.filereadable(cwd .. "/" .. file) == 1 or vim.fn.isdirectory(cwd .. "/" .. file) == 1 then
          vim.notify("Frontend project detected, setting gruvbox colorscheme", vim.log.levels.INFO)
          vim.cmd("colorscheme gruvbox")
          break
        end
      end
    end,
  })

  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      write_last_file()
    end,
  })

  api.nvim_create_user_command("LastFile", function()
    if not cache_path:exists() then
      vim.notify("No last_file cache found", vim.log.levels.INFO)
      return
    end

    local path = (cache_path:read() or ""):gsub("%s+$", "")
    if path == "" then
      vim.notify("Cached last_file is empty", vim.log.levels.INFO)
      return
    end

    vim.cmd.edit(fn.fnameescape(path))
  end, {})

  api.nvim_create_user_command("LastFileClear", function()
    if cache_path:exists() then
      cache_path:rm()
      vim.notify("Cleared last_file cache", vim.log.levels.INFO)
    else
      vim.notify("No last_file cache to clear", vim.log.levels.INFO)
    end
  end, {})

  api.nvim_create_user_command("OpenAnyCsFile", function()
    -- Opens any C# file to trigger Roslyn loading
    local cwd = fn.getcwd()
    local cs_files = vim.fn.globpath(cwd, "**/*.cs", false, true)
    if #cs_files == 0 then
      vim.notify("No C# files found in current directory", vim.log.levels.INFO)
      return
    end
    vim.cmd.edit(fn.fnameescape(cs_files[1]))
  end, {})
end

return M
