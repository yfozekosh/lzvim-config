local M = {}

--- Remembers the last real (non-`term://`, `oil://`, ...) file buffer and
--- writes it to `stdpath("cache")/last_file.txt` once on exit, instead of
--- writing to disk on every buffer switch.
function M.setup()
  local api = vim.api
  local fn = vim.fn

  local cache_path = fn.stdpath("cache") .. "/last_file.txt"
  local frontend_indicators = { "package.json", "node_modules", "index.html" }

  ---@param bufnr integer
  ---@return string?
  local function real_file(bufnr)
    if not api.nvim_buf_is_loaded(bufnr) then
      return nil
    end

    local name = api.nvim_buf_get_name(bufnr)
    -- skip unnamed buffers and pseudo-buffers such as term://, oil://, fugitive://
    if name == "" or name:match("^%a[%w+.-]*://") then
      return nil
    end

    return name
  end

  ---@param path string?
  local function write_last_file(path)
    if not path or fn.filereadable(path) == 0 then
      return
    end

    fn.mkdir(fn.fnamemodify(cache_path, ":h"), "p")
    fn.writefile({ path }, cache_path)
  end

  -- Captured here because the initial buffer's BufEnter fires before this
  -- plugin loads (it is loaded on VeryLazy).
  local last_file = real_file(api.nvim_get_current_buf())
  local checked_cwd = nil

  api.nvim_create_autocmd("BufEnter", {
    callback = function(args)
      last_file = real_file(args.buf) or last_file

      local cwd = fn.getcwd()
      if cwd == checked_cwd then
        return
      end
      checked_cwd = cwd

      for _, marker in ipairs(frontend_indicators) do
        if vim.uv.fs_stat(cwd .. "/" .. marker) then
          vim.notify("Frontend project detected, setting catppuccin colorscheme", vim.log.levels.INFO)
          vim.schedule(function()
            vim.cmd("colorscheme catppuccin-frappe")
          end)
          break
        end
      end
    end,
  })

  api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      write_last_file(last_file)
    end,
  })

  api.nvim_create_user_command("LastFile", function()
    if vim.uv.fs_stat(cache_path) == nil then
      vim.notify("No last_file cache found", vim.log.levels.INFO)
      return
    end

    local path = (fn.readfile(cache_path)[1] or ""):gsub("%s+$", "")
    if path == "" then
      vim.notify("Cached last_file is empty", vim.log.levels.INFO)
      return
    end

    vim.cmd.edit(fn.fnameescape(path))
  end, {})

  api.nvim_create_user_command("LastFileClear", function()
    if vim.uv.fs_stat(cache_path) ~= nil then
      fn.delete(cache_path)
      vim.notify("Cleared last_file cache", vim.log.levels.INFO)
    else
      vim.notify("No last_file cache to clear", vim.log.levels.INFO)
    end
  end, {})

  api.nvim_create_user_command("OpenAnyCsFile", function()
    -- Opens any C# file to trigger Roslyn loading
    local cwd = fn.getcwd()
    local cs_files = fn.globpath(cwd, "**/*.cs", false, true)
    if #cs_files == 0 then
      vim.notify("No C# files found in current directory", vim.log.levels.INFO)
      return
    end
    vim.cmd.edit(fn.fnameescape(cs_files[1]))
  end, {})
end

return M
