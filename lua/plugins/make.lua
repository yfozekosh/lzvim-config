-- GNU Make: autotools-language-server (targets/variables) + mbake formatting.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Installed through mason-lspconfig.nvim (Mason package:
        -- autotools-language-server). It also attaches to Makefile.am and
        -- configure.ac, where it knows autoconf/automake constructs.
        autotools_ls = {
          -- autotools-language-server (lsp-tree-sitter) mishandles
          -- incremental document edits: it computes Tree.edit() byte offsets
          -- against the already-updated buffer, corrupting the syntax tree
          -- and crashing the (Python) server on the next request. Force
          -- full-document sync so the server always reparses from scratch.
          flags = { allow_incremental_sync = false },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        -- conform's `bake` formatter runs the `mbake` binary.
        make = { "bake" },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "mbake" },
    },
  },
}
