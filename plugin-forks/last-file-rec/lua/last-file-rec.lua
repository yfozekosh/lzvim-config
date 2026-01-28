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

  api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      write_last_file(args.buf)
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

end

return M
