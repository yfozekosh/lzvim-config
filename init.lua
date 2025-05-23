-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Set root dir as the one that nvim was opened in.
local util = require("lazyvim.util")

local root = util.root.get()
vim.notify("Root: " .. root)
