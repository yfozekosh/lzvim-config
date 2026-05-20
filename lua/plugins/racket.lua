return {
  -- syntax highlighting
  -- { "wlangstroth/vim-racket" },

  -- lsp
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        racket_langserver = {},
      },
    },
  },
  "tpope/vim-repeat",

  -- treesitter scheme parser, safe merge
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "scheme" })
    end,
    init = function()
      -- Map racket filetype to use scheme parser
      vim.treesitter.language.register("scheme", "racket")
    end,
  },

  -- rainbow parens, lisp/scheme/racket only
  {
    "HiPhish/rainbow-delimiters.nvim",
    config = function()
      local rainbow = require("rainbow-delimiters")
      require("rainbow-delimiters.setup").setup({
        strategy = {
          [""] = nil, -- disabled globally
          scheme = rainbow.strategy["global"],
          racket = rainbow.strategy["global"],
        },
        query = {
          [""] = "rainbow-delimiters",
          scheme = "rainbow-delimiters",
          racket = "rainbow-delimiters",
        },
      })
    end,
  },

  -- Conjure for REPL integratioc> and interactive development
  {
    "Olical/conjure",
    ft = { "racket" },
    config = function()
      -- Configure Conjure for Racket
      vim.g["conjure#client#racket#stdio#command"] = "racket"
    end,
  },

-- -- -c> Structural editinc> with Parinfer (load eagerly to ensure availability)
-- {
--   "eraserhd/parinfer-rust",
--   build = "cargo build --release",
--   init = function()
--     -- Set configuration early before plugin loads
--     vim.g.parinfer_enabled = 1
--     vim.g.parinfer_mode = "smart"
--   end,
--   config = function()
--     -- Ensure it's initialized for Racket files that are already open
--     if vim.bo.filetype == "racket" then
--       vim.cmd("doautocmd FileType racket")
--     end
--   end,
-- },

  -- vim-sexp for explicit structural editing (move, wrap, splice, etc.)
  {
    "Grazfather/sexp.nvim",
    config = {
      enable_insert_mode_mappings = true,
      insert_after_wrap = true,
      filetypes = "clojure,scheme,lisp,timl,fennel,racket",
      maxlines = -1,
      mappings = {}, -- See below
    },
    ft = { "racket" },
    -- init c> function()
    --   -- Disable default insert mode mappings to avoid conflicts with Parinfer
    --   vim.g.sexp_enable_insert_mode_mappings = 0
    --   -- Add racket to the list of supported filetypes for vim-sexp
    --   vim.g.sexp_filetypes = "clojure,scheme,lisp,timl,fennel,racket"
    -- end,
  },

  -- Highlight matching parenthesis under cursor (Racket only)
  {
    "monkoose/matchparen.nvim",
    ft = { "racket" },
    config = function()
      require("matchparen").setup({})
    end,
  },
}
