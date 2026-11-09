-- Neovim's built-in asm detector scans the first 50 lines and treats
-- directives such as `.macro` as VAX Macro Assembly (`vmasm`).  GNU RISC-V
-- assembly uses those directives too, so keep .s/.S files on the normal asm
-- filetype instead.
vim.filetype.add({
  pattern = {
    [".*%.s"] = "asm",
    [".*%.S"] = "asm",
  },
})
