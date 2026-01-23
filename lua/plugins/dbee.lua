return {
  {
    "kndndrj/nvim-dbee",
    enabled = false,
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    build = function()
      -- Install tries to automatically detect the install method.
      -- if it fails, try calling it with one of these parameters:
      --    "curl", "wget", "bitsadmin", "go"
      require("dbee").install()
    end,
    config = function()
      require("dbee").setup(--[[optional config]])
      require("dbee.sources").FileSource:new(vim.fn.stdpath("cache") .. "/dbee/persistence.json")
    end,
  },
  {
    dir = "~/.config/nvim/plugin-forks/nvim-dbee/",
    enabled = true,
    name="yf-dbee.nvim",
    build = function()
      -- Install tries to automatically detect the install method.
      -- if it fails, try calling it with one of these parameters:
      --    "curl", "wget", "bitsadmin", "go"
      require("dbee").install("go")
    end,
    config = function()
      require("dbee").setup(--[[optional config]])
    end,
  },
}
