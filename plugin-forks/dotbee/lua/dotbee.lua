local dotbee = {
  ui = require("dotbee.ui")
}

function dotbee.setup(cfg)
  vim.notify("dotbee setup called")
  dotbee.ui.add_on_enter(function()
    vim.notify("Dotbee UI entered")
  end)
end

function dotbee.install(method)
  vim.notify("dotbee install called with method: " .. tostring(method))
end

function dotbee.toggle()
  dotbee.ui.toggle()
  -- start the job
end

return dotbee
