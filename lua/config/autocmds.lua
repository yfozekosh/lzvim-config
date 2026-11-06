-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--

-- GNU ld linker scripts: make sure autoindent works even when the
-- `linkerscript` treesitter parser is not installed yet. LazyVim only sets
-- the treesitter indentexpr when `have("indents")` is true; otherwise it
-- leaves the buffer with no indentexpr at all. Fall back to Neovim's built-in
-- brace-counting indent (indent/ld.vim) in that case.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "ld",
  callback = function(ev)
    local ok, ts = pcall(require, "lazyvim.util.treesitter")
    if ok and ts.have and ts.have("ld", "indents") then
      vim.bo[ev.buf].indentexpr = "v:lua.LazyVim.treesitter.indentexpr()"
    elseif vim.fn.exists("*GetLDIndent") == 1 then
      vim.bo[ev.buf].indentexpr = "GetLDIndent()"
    end
    vim.bo[ev.buf].indentkeys = "0{,0},!^F,o,O"
  end,
  desc = "Ensure autoindent for ld linker scripts",
})

-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local function reload_lsp_and_treesitter()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      -- Get clients attached to this buffer using new API
      local clients = vim.lsp.get_clients({ bufnr = buf })

      for _, client in pairs(clients) do
        if client.supports_method and client.supports_method("textDocument/didClose") then
          client.notify("textDocument/didClose", { textDocument = { uri = vim.uri_from_bufnr(buf) } })
          client.notify("textDocument/didOpen", { textDocument = vim.lsp.util.make_text_document_params(buf) })
        end
      end

      -- Reload Treesitter parser for this buffer
      local ts = require("nvim-treesitter.parsers")
      local parser = ts.get_parser(buf)
      if parser then
        parser:reload()
      end
    end
  end

  vim.notify("LSP and Treesitter reloaded after session restore", vim.log.levels.INFO, { title = "Persistence" })
end

vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = reload_lsp_and_treesitter,
})

-- PlatformIO: keep compile_commands.json fresh so clangd can resolve headers.
--
-- clangd needs a compilation database; without one every `#include` in a
-- PlatformIO project is reported as "file not found". `pio run -t compiledb`
-- writes it, but it goes stale whenever `platformio.ini` changes (new env,
-- new flags, new framework), so regenerate it in the background whenever a
-- C/C++ buffer of a PlatformIO project is opened and the database is missing
-- or older than `platformio.ini`. clangd watches the file and reloads it, so
-- no LSP restart is needed.
--
-- Note: PlatformIO also needs a project-local `.clangd` to strip the WCH
-- RISC-V flags clangd cannot parse - see the README section
-- "PlatformIO / clangd (C/C++)". This autocmd only handles the database.
local pio_filetypes = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }

local pio_augroup = vim.api.nvim_create_augroup("yf_platformio_compiledb", { clear = true })

-- root dir -> true while `pio run -t compiledb` is running there
local pio_running = {}
-- root dir -> true once generation failed, so the next buffer in the same
-- project does not spawn the same failing build again (`:PlatformIOCompiledb`
-- clears it)
local pio_failed = {}
local pio_cli_missing = false

local function pio_root(dir)
  local ini = vim.fs.find("platformio.ini", { path = dir, upward = true, type = "file" })[1]
  return ini and vim.fs.dirname(ini) or nil
end

local function pio_db_stale(root)
  local db = vim.uv.fs_stat(root .. "/compile_commands.json")
  if not db then
    return true
  end
  local ini = vim.uv.fs_stat(root .. "/platformio.ini")
  return ini ~= nil and ini.mtime.sec > db.mtime.sec
end

local function pio_ensure_db(root)
  if pio_running[root] or pio_failed[root] or not pio_db_stale(root) then
    return
  end

  if vim.fn.executable("pio") == 0 then
    if not pio_cli_missing then
      pio_cli_missing = true
      vim.notify(
        "PlatformIO CLI (`pio`) not found - skipping compile_commands.json generation",
        vim.log.levels.WARN,
        { title = "PlatformIO" }
      )
    end
    return
  end

  pio_running[root] = true
  vim.notify(
    "Generating compile_commands.json for clangd (`pio run -t compiledb`)...",
    vim.log.levels.INFO,
    { title = "PlatformIO" }
  )

  vim.system({ "pio", "run", "-t", "compiledb" }, { cwd = root, text = true }, function(res)
    pio_running[root] = nil
    vim.schedule(function()
      if res.code == 0 then
        vim.notify(
          "compile_commands.json is up to date - clangd reloads it automatically",
          vim.log.levels.INFO,
          { title = "PlatformIO" }
        )
        return
      end
      -- `pio` buries the useful error at the end of a long build log
      local output = (res.stderr ~= "" and res.stderr) or res.stdout or ""
      local lines = vim.split(vim.trim(output), "\n")
      local tail = vim.list_slice(lines, math.max(#lines - 9, 1))
      pio_failed[root] = true
      vim.notify(
        string.format(
          "`pio run -t compiledb` failed (exit %d), not retrying in this session - run :PlatformIOCompiledb to retry:\n%s",
          res.code or -1,
          table.concat(tail, "\n")
        ),
        vim.log.levels.ERROR,
        { title = "PlatformIO" }
      )
    end)
  end)
end

local function pio_maybe_generate(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not pio_filetypes[vim.bo[buf].filetype] then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  -- skip generated sources inside .pio/ and unnamed buffers
  if name == "" or name:find("/.pio/", 1, true) then
    return
  end
  local root = pio_root(vim.fs.dirname(name))
  if root then
    pio_ensure_db(root)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = pio_augroup,
  pattern = "c,cpp,objc,objcpp,cuda",
  callback = function(args)
    pio_maybe_generate(args.buf)
  end,
})

-- saving platformio.ini is what makes the database stale in the first place
vim.api.nvim_create_autocmd("BufWritePost", {
  group = pio_augroup,
  pattern = "platformio.ini",
  callback = function(args)
    local root = vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf))
    pio_failed[root] = nil
    pio_ensure_db(root)
  end,
})

vim.api.nvim_create_user_command("PlatformIOCompiledb", function()
  local name = vim.api.nvim_buf_get_name(0)
  local root = name ~= "" and pio_root(vim.fs.dirname(name))
  if not root then
    vim.notify("No platformio.ini found above this buffer", vim.log.levels.WARN, { title = "PlatformIO" })
    return
  end
  -- force: ignore the staleness check and any earlier failure
  pio_failed[root] = nil
  vim.uv.fs_unlink(root .. "/compile_commands.json")
  pio_ensure_db(root)
end, { desc = "Regenerate compile_commands.json for the current PlatformIO project" })

-- The file above (and this one) is sourced on VeryLazy, so FileType has
-- already fired for the file nvim was started with - sweep the open buffers.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    pio_maybe_generate(buf)
  end
end
