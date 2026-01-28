return {
  {
    dir = vim.fn.stdpath("config") .. "/plugin-forks/last-file-rec/",
    lazy = false,
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("last-file-rec").setup()
    end,
  },
}
