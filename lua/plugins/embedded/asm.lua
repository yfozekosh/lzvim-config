-- Assembly (GNU as / RISC-V) and linker-script support.
--
-- * `asm` is the tree-sitter grammar for GNU assembler syntax. It covers
--   generic GAS directives, labels, instructions and registers, which is
--   also what RISC-V assembly uses.
-- * `linkerscript` is the grammar for GNU ld scripts (filetype `ld`).
--   nvim-treesitter already registers it for the `ld` filetype; see
--   `ftdetect/linker.lua` for the extra extensions.
-- * `asm-lsp` adds hover/completion/goto-definition for GAS assembly. It is
--   configured for RISC-V in `asm-lsp/.asm-lsp.toml` (symlinked into
--   ~/.config/asm-lsp by setup.sh) and installed by setup.sh rather than
--   Mason, so it is excluded from Mason below.
-- * asm-lsp upstream only ships base-ISA docs, so `lua/riscv_asm/` adds the
--   GAS pseudo-instructions (`la`, `li`, `mv`, `ret`, ...), ABI register
--   names (`a0`, `t0`, ...) and common CSRs to hover and blink.cmp
--   completion (upstream asm-lsp issue #261).
-- * `lua/asm_symbols/` adds project-wide completion from the linked ELF:
--   labels defined in other `.s`/`.S` files and functions/globals from C
--   (after a successful build). Auto-brackets are disabled for `asm`.
-- * `rvfmt` (https://github.com/mattfbacon/riscv-asm-fmt) formats RISC-V
--   assembly through conform.nvim. setup.sh builds a patched copy so that
--   symbols such as `__global_pointer$` are accepted by its lexer.

return {
  {
    "folke/which-key.nvim",
    optional = true,
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, {
        "gR",
        desc = "Project-wide references (asm)",
        cond = function()
          return vim.bo.filetype == "asm"
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "asm", "linkerscript" })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.api.nvim_create_user_command("RiscvAsmDoctor", function()
        require("riscv_asm").doctor()
      end, { desc = "Explain why RISC-V asm-lsp has (or has not) any diagnostics" })
      vim.api.nvim_create_user_command("RiscvAsmReferences", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local word = vim.fn.expand("<cword>")
        local ok, asm_docs = pcall(require, "asm_docs")
        local items = {}
        if ok then
          for _, r in ipairs(asm_docs.references(word, bufnr)) do
            items[#items + 1] = {
              filename = r.filename,
              lnum = r.lnum,
              col = r.col,
              text = r.text,
            }
          end
        end
        if #items == 0 then
          vim.notify("No references found")
        else
          vim.fn.setqflist({}, " ", { title = "References", items = items })
          vim.cmd("botright copen")
        end
      end, { desc = "Project-wide references for the symbol under the cursor" })
    end,
    opts = {
      servers = {
        -- Installed into ~/.local/bin by setup.sh's install_riscv_asm_tools
        -- migration; don't let Mason build a second copy.
        asm_lsp = {
          mason = false,
          -- asm-lsp only finds a compilation database at its root, so treat
          -- the database files as root markers too. Without one it cannot
          -- run a compiler and will publish no diagnostics.
          root_markers = { ".asm-lsp.toml", "compile_flags.txt", "compile_commands.json", ".git" },
          keys = {
            {
              "K",
              function()
                require("riscv_asm").hover_current()
              end,
              desc = "Hover (RISC-V pseudo/register/CSR)",
            },
            {
              "gd",
              function()
                local word = vim.fn.expand("<cword>")
                local ok, asm_docs = pcall(require, "asm_docs")
                if ok and asm_docs.goto_definition(word, vim.api.nvim_get_current_buf()) then
                  return
                end
                vim.lsp.buf.definition()
              end,
              desc = "Goto definition (project symbols)",
            },
            {
              "gR",
              function()
                local bufnr = vim.api.nvim_get_current_buf()
                local word = vim.fn.expand("<cword>")
                local ok, asm_docs = pcall(require, "asm_docs")
                local items = {}
                if ok then
                  for _, r in ipairs(asm_docs.references(word, bufnr)) do
                    items[#items + 1] = {
                      filename = r.filename,
                      lnum = r.lnum,
                      col = r.col,
                      text = r.text,
                    }
                  end
                end
                if #items == 0 then
                  vim.notify("No references found")
                else
                  vim.fn.setqflist({}, " ", { title = "References", items = items })
                  vim.cmd("botright copen")
                end
              end,
              desc = "Project-wide references",
            },
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        asm = { "rvfmt" },
        ld = { "ldformat" },
      },
      formatters = {
        ldformat = {
          command = "ld-format",
          stdin = true,
        },
        rvfmt = {
          command = "rvfmt",
          stdin = true,
          -- rvfmt parses GAS/RISC-V, not AT&T x86; leave x86 buffers alone
          -- instead of rejecting `$imm` or mangling `%rax`.
          condition = function(_, ctx)
            return not require("riscv_asm").is_x86_asm(ctx.buf)
          end,
        },
      },
    },
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      completion = {
        accept = {
          auto_brackets = {
            blocked_filetypes = { "asm" },
          },
        },
      },
      sources = {
        per_filetype = {
          asm = { "riscv_asm", "asm_symbols", "asm_macros", inherit_defaults = true },
        },
        providers = {
          riscv_asm = {
            name = "RISC-V",
            module = "riscv_asm",
            score_offset = 10,
          },
          asm_symbols = {
            name = "ELF symbols",
            module = "asm_symbols",
            score_offset = 5,
          },
          asm_macros = {
            name = "Macros",
            module = "asm_macros",
            score_offset = 6,
          },
        },
      },
    },
  },
}
