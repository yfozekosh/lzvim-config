-- Sessions aren't used (files are opened via the dashboard's `w` / directly).
-- LazyVim enables persistence.nvim by default, which writes a session file
-- on every exit; turn it off along with its <leader>q* keymaps.
return {
  "folke/persistence.nvim",
  enabled = false,
}
