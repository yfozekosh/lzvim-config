local floatbuf = require("dotbee.ui.floatbuf")

local M = {
  toggle = function()
    floatbuf.toggle()
  end,
  is_open = function()
    vim.notify("dotbee UI is_open called")
    return false
  end,
  add_on_enter = floatbuf.add_on_enter,
}

return M
