return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "Issafalcon/neotest-dotnet",
    },
    opts = function(_, opts)
      table.insert(
        opts.adapters,
        require("neotest-dotnet")({
          dap = { -- optional: use dap to attach for test debugging
            justMyCode = false,
          },
        })
      )
    end,
  },
}
