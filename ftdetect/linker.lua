-- Neovim already detects *.ld and /ldscripts/ as `ld`, but embedded projects
-- commonly use *.lds, *.lds.S (preprocessed) and *.ldscript. Map those to `ld`
-- as well so the linkerscript tree-sitter parser and syntax/ld.vim apply.
vim.filetype.add({
  extension = {
    lds = "ld",
    ldscript = "ld",
  },
  pattern = {
    [".*%.lds%.S"] = "ld",
    [".*%.ld%.S"] = "ld",
  },
})
