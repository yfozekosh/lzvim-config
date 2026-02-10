return {
  { "nvim-neotest/nvim-nio" },
  {
    "Issafalcon/neotest-dotnet",
    dir = vim.fn.stdpath("config") .. "/plugin-forks/neotest-dotnet/",
    lazy = false,
    dependencies = {
      "nvim-neotest/neotest",
    },
  },
  {
    "nvim-neotest/neotest",
    dir = vim.fn.stdpath("config") .. "/plugin-forks/neotest/",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "Issafalcon/neotest-dotnet",
    },
    config = function()
---@diagnostic disable-next-line: missing-fields
      require("neotest").setup({
        adapters = {
          require("neotest-dotnet")({
            -- Optionally configure dotnet test adapter here
          }),
        },
      })
    end,
  },
}
