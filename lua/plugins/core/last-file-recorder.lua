return {
  {
    dir = vim.fn.stdpath("config") .. "/plugin-forks/last-file-rec/",
    event = "VeryLazy",
    config = function()
      require("last-file-rec").setup()
    end,
  },
}
