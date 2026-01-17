return {
{ "nvim-neotest/nvim-nio" },
-- {
--   "mfussenegger/nvim-dap",
--   event = "VeryLazy",
--   dependencies = {
--     "rcarriga/nvim-dap-ui",
--   },
--   config = function()
--     require("config.nvim-dap") -- You should have this file
--   end,
-- },
-- {
--   "rcarriga/nvim-dap-ui",
--   dependencies = {
--     "mfussenegger/nvim-dap",
--   },
--   config = function()
--   end,
-- },
-- { "nvim-neotest/nvim-nio" },
{
  "Issafalcon/neotest-dotnet",
  lazy = false,
  dependencies = {
    "nvim-neotest/neotest",
  },
},
{
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "Issafalcon/neotest-dotnet",
  },
  config = function()
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
