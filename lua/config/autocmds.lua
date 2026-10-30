-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--

-- Create custom highlight group for s-expression highlighting
vim.api.nvim_set_hl(0, "RacketSexpHL", {
  bg = "#3e4452",      -- Dark background
  fg = "NONE",
  bold = true,
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

vim.api.nvim_create_autocmd("FileType", {
  pattern = "racket",
  callback = function()
    local term_buf = nil

    -- Enable matchparen highlighting for parenthesis under cursor
    vim.opt_local.matchpairs = vim.opt.matchpairs + { "<:>" }

    -- Ensure Parinfer is enabled
    vim.g.parinfer_enabled = 1
    vim.g.parinfer_mode = "smart"

    -- Load and set up the help toggle
    local toggle_help = require("config.ComplexKeymaps.racket-help")
    vim.keymap.set("n", "<leader>?", toggle_help, { buffer = true, desc = "Toggle Racket help" })
    
    -- Diagnostic command to check Parinfer status
    vim.api.nvim_buf_create_user_command(0, "ParinferStatus", function()
      local status = {
        "Parinfer Status:",
        "  Enabled: " .. tostring(vim.g.parinfer_enabled),
        "  Mode: " .. (vim.g.parinfer_mode or "not set"),
        "  Library: " .. (vim.g.parinfer_dylib_path or "not loaded"),
      }
      vim.notify(table.concat(status, "\n"), vim.log.levels.INFO)
    end, {})

    -- Debug command to check s-expression highlighting
    vim.api.nvim_buf_create_user_command(0, "DebugSexpHL", function()
      local ok, ts = pcall(require, "vim.treesitter")
      if not ok then
        vim.notify("Treesitter not available", vim.log.levels.ERROR)
        return
      end
      
      local ok_parser, parser = pcall(ts.get_parser, 0)
      if not ok_parser or not parser then
        vim.notify("Parser not available", vim.log.levels.ERROR)
        return
      end
      
      local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.notify(string.format("Cursor at row=%d, col=%d", cursor_row-1, cursor_col), vim.log.levels.INFO)
    end, {})

    -- S-expression highlighting using Treesitter
    local sexp_highlight_ns = vim.api.nvim_create_namespace("racket_sexp_highlight")
    local sexp_highlight_enabled = true

    local function highlight_current_sexp_treesitter()
      if not sexp_highlight_enabled then return end
      
      vim.api.nvim_buf_clear_namespace(0, sexp_highlight_ns, 0, -1)
      
      local ok, ts = pcall(require, "vim.treesitter")
      if not ok then return end
      
      local ok_parser, parser = pcall(ts.get_parser, 0)
      if not ok_parser or not parser then return end
      
      local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
      cursor_row = cursor_row - 1  -- Convert to 0-indexed
      
      -- Find the smallest node at cursor position
      local root = parser:parse()[1]:root()
      
      local function find_smallest_sexp_at_cursor(node)
        if not node then return nil end
        
        local start_row, start_col, end_row, end_col = node:range()
        
        -- Check if cursor is within this node
        local in_node = false
        if start_row == end_row then
          in_node = (cursor_row == start_row) and 
                   (cursor_col >= start_col) and 
                   (cursor_col < end_col)
        else
          if cursor_row == start_row then
            in_node = cursor_col >= start_col
          elseif cursor_row == end_row then
            in_node = cursor_col < end_col
          else
            in_node = cursor_row > start_row and cursor_row < end_row
          end
        end
        
        if not in_node then return nil end
        
        -- Check if this node is an s-expression
        local node_type = node:type()
        local is_sexp = node_type == "list" or node_type == "quoted" or node_type == "quasiquoted"
        
        -- Search children first (to find smallest)
        for child in node:iter_children() do
          local match = find_smallest_sexp_at_cursor(child)
          if match then
            return match  -- Return first match found (smallest)
          end
        end
        
        -- If no children matched but this is an s-expression, return it
        if is_sexp then
          return node
        end
        
        return nil
      end
      
      local sexp_node = find_smallest_sexp_at_cursor(root)
      
      if sexp_node then
        local start_row, start_col, end_row, end_col = sexp_node:range()
        
        -- Apply highlight with custom group - whole s-expression
        if start_row == end_row then
          vim.api.nvim_buf_set_extmark(0, sexp_highlight_ns, start_row, start_col, {
            end_col = end_col,
            hl_group = "RacketSexpHL",
            priority = 100,
          })
        else
          vim.api.nvim_buf_set_extmark(0, sexp_highlight_ns, start_row, start_col, {
            end_line = end_row,
            end_col = end_col,
            hl_group = "RacketSexpHL",
            priority = 100,
          })
        end
      end
    end

    -- Toggle command
    vim.api.nvim_buf_create_user_command(0, "ToggleSexpHighlight", function()
      sexp_highlight_enabled = not sexp_highlight_enabled
      if sexp_highlight_enabled then
        highlight_current_sexp_treesitter()
        vim.notify("S-expression highlighting enabled", vim.log.levels.INFO)
      else
        vim.api.nvim_buf_clear_namespace(0, sexp_highlight_ns, 0, -1)
        vim.notify("S-expression highlighting disabled", vim.log.levels.INFO)
      end
    end, {})

    -- Highlight on cursor move
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = 0,
      callback = highlight_current_sexp_treesitter,
    })

    vim.keymap.set("n", "<leader>r", function()
      local file = vim.fn.expand("%:p")
      local source_win = vim.api.nvim_get_current_win()
      vim.cmd("w")

      local reuse = false
      if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
        local chan = vim.bo[term_buf].channel
        if chan and chan > 0 then
          local ok = pcall(vim.fn.chansend, chan, "racket " .. vim.fn.shellescape(file) .. "\n")
          if ok then
            reuse = true
            local term_win = nil
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(win) == term_buf then
                term_win = win
                break
              end
            end
            if not term_win then
              vim.cmd("split")
              vim.api.nvim_win_set_buf(0, term_buf)
              vim.api.nvim_win_set_height(0, math.floor(vim.o.lines / 4))
            end
          end
        end
      end

      if not reuse then
        if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
          vim.api.nvim_buf_delete(term_buf, { force = true })
        end
        vim.cmd("split")
        vim.cmd("terminal racket " .. vim.fn.shellescape(file))
        term_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_win_set_height(0, math.floor(vim.o.lines / 4))
        -- q closes the window
        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = term_buf, desc = "Close terminal" })
      end

      vim.api.nvim_set_current_win(source_win)
    end, { buffer = true, desc = "Run current Racket file" })
  end,
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
