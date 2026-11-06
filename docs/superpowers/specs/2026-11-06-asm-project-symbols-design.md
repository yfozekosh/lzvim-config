# Project symbol completion for assembly — design

Date: 2026-11-06
Status: proposed

## Intent

While writing RISC-V assembly in a mixed C/asm firmware, I want completion
for symbols defined elsewhere in the project: labels in other `.s`/`.S`
files and functions/globals from C. asm-lsp has no project index — its
completion only covers instructions, registers, directives and the current
file — so it cannot supply these.

I rebuild often from a keymap (`<leader>cb`), so indexing the linked ELF is
an acceptable source of truth and is more accurate than parsing C by hand.

## Goals

- A blink.cmp source, `asm_symbols`, enabled for the `asm` filetype.
- Index defined symbols from the project's newest built ELF, found with the
  same discovery and root logic the disassembly view already uses.
- Present functions as `Function`, objects as `Variable`, and absolute
  symbols as `Constant`; show symbol type and address in the detail text.
- Re-index when the ELF's mtime changes, so a rebuild is reflected without
  restarting Neovim. Completion never blocks the editor.
- Configure via `vim.g.asm_symbols` (`elf`, `nm`); both default to
  auto-detection (newest of `out/*.elf`, `build/*.elf`, `*.elf`; first
  working `*-nm` from the RISC-V toolchain, then host `nm`).
- Report index status (ELF, nm, symbol count) from `:RiscvAsmDoctor`.

## Non-goals

- Jump-to-definition, hover or references for project symbols. asm-lsp keeps
  handling instructions; navigation can be added later.
- Parsing unbuilt sources. A symbol appears only after a successful link.
- C macros, `#define` constants and asm `.equ` values — they are not ELF
  symbols.
- In-file labels that the assembler discards (`.L...`); asm-lsp continues to
  handle the current file.
- Changing asm-lsp or vendoring another language server.

## Approaches considered

1. **Extend the existing `riscv_asm` blink source** with ELF symbols. Least
   wiring, but mixes instruction documentation with project indexing and
   makes both harder to test or disable.
2. **Parse project sources with tree-sitter/regex.** Works before a build,
   but needs a C parser, ignores preprocessing, and misses compiler-generated
   and renamed symbols. Rejected earlier in favour of after-build symbols.
3. **Separate `lua/asm_symbols/` module implementing its own blink source.**
   Clear boundary, independent config and tests, reuses `disasm.config` for
   ELF discovery. Chosen.

## How it works

- `find_elf` from `lua/disasm/config.lua` supplies candidates; the newest by
  `mtime` wins (or `vim.g.asm_symbols.elf` when set).
- `nm --defined-only -S --format=posix` output is parsed into
  `name, type, address, size`; duplicate names are dropped (newest ELF
  first).
- The source runs `nm` asynchronously with `vim.system`, caches items keyed
  by ELF path plus mtime, and returns a deep copy per request because
  blink.cmp mutates returned items.
- On a failed or missing ELF/nm, completion returns no items silently;
  `:RiscvAsmDoctor` explains why.
- `lua/plugins/asm.lua` registers the provider in the `asm` filetype list
  next to `riscv_asm`.

## Testing

A plain-Lua test (`tests/asm_symbols/run.lua`, same harness style as
`tests/disasm/run.lua`) covers nm parsing, kind mapping, deduplication and
newest-ELF selection without needing a toolchain. Manual check in
`~/Projects/mtrx_asm`: `delay`, `_start`, `lool`, `main1` complete after
`:Build`.
