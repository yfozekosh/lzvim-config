-- Global lock + last-run timestamps (autowrite can trigger many saves)
vim.g._raco_fmt_lock = vim.g._raco_fmt_lock or false
vim.g._raco_fmt_last = vim.g._raco_fmt_last or {}

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "racket", "scheme", "lisp", "clojure" },
  callback = function(ev)
    -- local indent tweaks (optional)
    vim.bo[ev.buf].indentexpr = ""
    vim.opt_local.lisp = true
    vim.opt_local.autoindent = true
    vim.opt_local.lispwords =
      "define,lambda,let,let*,letrec,begin,cond,and,or,when,unless,define-syntax,let-syntax,letrec-syntax,syntax-rules"

    -- enable/disable autoformat per buffer
    vim.b[ev.buf].autoformat = true

    local function format_with_raco_fmt(opts)
      opts = opts or {}
      local silent = opts.silent ~= false -- default: true (mute errors)

      -- no formatter? just skip silently
      if vim.fn.executable("raco") ~= 1 then
        if not silent then
          vim.notify("raco not found in PATH", vim.log.levels.WARN)
        end
        return
      end

      -- avoid formatting unnamed / non-file buffers
      local fname = vim.api.nvim_buf_get_name(ev.buf)
      if fname == nil or fname == "" then
        return
      end

      -- per-buffer recursion guard
      if vim.b[ev.buf].racket_formatting then
        return
      end

      -- global lock: autowrite can trigger overlapping saves across buffers
      if vim.g._raco_fmt_lock then
        return
      end

      -- debounce (milliseconds)
      local now = vim.uv.now()
      local last = vim.g._raco_fmt_last[ev.buf] or 0
      if (now - last) < 300 then
        return
      end
      vim.g._raco_fmt_last[ev.buf] = now

      vim.b[ev.buf].racket_formatting = true
      vim.g._raco_fmt_lock = true

      local ok, err = pcall(function()
        local view = vim.fn.winsaveview()
        local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)

        -- temp file for stable formatting
        local tmp = vim.fn.tempname() .. ".rkt"
        vim.fn.writefile(lines, tmp)

        -- run formatter (list form avoids shell issues)
        local out = vim.fn.system({ "raco", "fmt", "-i", tmp })
        if vim.v.shell_error ~= 0 then
          if not silent then
            vim.notify("raco fmt failed: " .. out, vim.log.levels.ERROR)
          end
          return
        end

        local formatted = vim.fn.readfile(tmp)

        -- only update buffer if content actually changed (reduces churn with autowrite)
        if #formatted == #lines then
          local same = true
          for i = 1, #lines do
            if lines[i] ~= formatted[i] then
              same = false
              break
            end
          end
          if same then
            vim.fn.winrestview(view)
            return
          end
        end

        vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, formatted)
        vim.fn.winrestview(view)
      end)

      vim.g._raco_fmt_lock = false
      vim.b[ev.buf].racket_formatting = false

      if not ok and not silent then
        vim.notify("formatter crashed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end

    -- manual format (shows errors)
    vim.keymap.set("n", "<leader>cf", function()
      format_with_raco_fmt({ silent = false })
      vim.notify("Formatted with raco fmt", vim.log.levels.INFO)
    end, { buffer = ev.buf, desc = "Format buffer (raco fmt)" })

    -- format on save (silent) — BufWritePre is the right hook
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = ev.buf,
      callback = function()
        if vim.b[ev.buf].autoformat then
          format_with_raco_fmt({ silent = true })
        end
      end,
    })
  end,
})
