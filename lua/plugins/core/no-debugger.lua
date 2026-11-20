-- No in-editor debugging or test running: debug/test from the CLI instead.
-- The LazyVim `dap.*` and `test.*` extras are not enabled (lazyvim.json), but
-- language extras still reference these optionally, and nvim-dap-python's
-- own packaged lazy spec re-enables nvim-dap as a hard dependency once it is
-- installed - so disable them explicitly.
return {
  { "mfussenegger/nvim-dap", enabled = false },
  { "mfussenegger/nvim-dap-python", enabled = false },
  { "nvim-neotest/neotest", enabled = false },
}
