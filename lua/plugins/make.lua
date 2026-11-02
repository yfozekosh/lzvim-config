-- GNU Make: autotools-language-server (targets/variables) + mbake formatting.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Installed through mason-lspconfig.nvim (Mason package:
        -- autotools-language-server). It also attaches to Makefile.am and
        -- configure.ac, where it knows autoconf/automake constructs.
        autotools_ls = {},
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
