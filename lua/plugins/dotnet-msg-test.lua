return {
    dir = "~/.config/nvim/plugin-forks/dotbee/",
    enabled = true,
    name="dotbee.nvim",
    build = function()
      -- Install tries to automatically detect the install method.
      -- if it fails, try calling it with one of these parameters:
      --    "curl", "wget", "bitsadmin", "go"
      require("dotbee").install()
    end,
    config = function()
      require("dotbee").setup(--[[optional config]])
    end,
}
