-- Raspberry Pi and other explicitly minimal machines run a plugin-free
-- config: LazyVim needs Neovim >= 0.11.2, Debian trixie ships 0.10.4, and
-- the Pi has ~91 MB RAM free. YF_NVIM_MINIMAL=1/0 overrides detection.
local minimal = require("config.minimal")
if minimal.enabled() then
  vim.g.yf_minimal = true
  minimal.setup()
  return
end

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
