# Assembly & linker scripts (GNU as, RISC-V)

GNU assembler (including RISC-V) and GNU ld linker scripts get tree-sitter
highlighting, an LSP and a formatter.

## Tree-sitter highlighting

- `lua/plugins/asm.lua` adds the `asm` and `linkerscript` parsers to
  nvim-treesitter's `ensure_installed` (lazy installs them on first launch).
- Neovim already detects `*.s`, `*.S` and `*.asm` as `asm`, and `*.ld` /
  `ldscripts/` as `ld`. `ftdetect/linker.lua` adds the common embedded
  variants `*.lds`, `*.lds.S`, `*.ld.S` and `*.ldscript` as `ld`.
- `after/queries/asm/highlights.scm` refines the generic GAS highlights:
  directives (`.section`, `.globl`, ...) use `@keyword`, and standard RISC-V
  CSRs (`mstatus`, `mepc`, `satp`, `pmpcfg0`, `hpmcounter3`, ...) use
  `@constant.builtin` instead of looking like general-purpose registers.

`.S` files are preprocessed by the C compiler. The asm grammar treats
`#include` / `#define` lines as comments, so they are highlighted as comments
rather than C preprocessor directives; the assembly around them still
highlights normally.

## RISC-V LSP & formatter

RISC-V GNU assembler (`.s`/`.S`) gets both an LSP and a formatter. Both tools
are installed by `setup.sh`'s `install_riscv_asm_tools` migration into
`~/.local/bin`.

### LSP: asm-lsp

`asm-lsp` (`lua/plugins/asm.lua`) provides hover documentation, completion
and goto-definition for GAS instructions, registers and directives,
including RISC-V. The global config `asm-lsp/.asm-lsp.toml` is symlinked to
`~/.config/asm-lsp/.asm-lsp.toml` by `setup.sh` and sets
`instruction_set = "riscv"`; without it asm-lsp defaults to the host
architecture. It is marked `mason = false` in the plugin spec, so Mason does
not build a duplicate.

Upstream's RISC-V database only covers base-ISA mnemonics, so
`lua/riscv_asm/` supplements hover (`K`) and blink.cmp completion with the
common scalar GAS pseudo-instructions (`la`, `li`, `mv`, `ret`, `call`,
...), ABI register names (`a0`, `t0`, `fa0`, ...) and common CSRs
(see [asm-lsp issue #261](https://github.com/bergercookie/asm-lsp/issues/261)).
`K` prefers the supplement's pseudo-instruction/ABI-register/CSR docs and
falls back to asm-lsp's hover for real instructions. blink.cmp gets the same
entries through the `riscv_asm` source, scoped to the `asm` filetype. Like
the formatter, it skips buffers that look like x86 assembly.

### Formatter: rvfmt

`rvfmt` ([riscv-asm-fmt](https://github.com/mattfbacon/riscv-asm-fmt)) runs
through `conform.nvim` for the `asm` filetype, so LazyVim's format-on-save
and `<leader>cf` both work. `setup.sh` builds it from a pinned commit with
`patches/riscv-asm-fmt-dollar-symbol.patch`, because upstream's lexer rejects
`$` in identifiers and therefore fails on the standard `__global_pointer$`
linker symbol.

## Notes

- Autoformat is on by default (LazyVim's `vim.g.autoformat`). Disable it for
  one buffer with `:lua vim.b.autoformat = false`, or toggle formatting for
  the session with LazyVim's `<leader>uf`.
- `rvfmt` parses GAS/RISC-V, not AT&T x86. `lua/plugins/asm.lua` skips it for
  buffers that look like x86 (e.g. `$1` immediates or `%rax` operands), so
  x86 assembly is left untouched.
- `rvfmt` does not understand GAS macro parameters (`\arg`); on a `.macro`
  body that uses them it exits with an error and the buffer is left
  unchanged. Format those files manually or disable autoformat for them.
- `asm-lsp` has no parser-based error checking: its diagnostics come from
  running a real assembler and parsing stderr. The implicit host
  `gcc`/`clang` fallback is disabled (`default_diagnostics = false`) because
  the host compiler rejects every RISC-V mnemonic. To get compiler errors,
  provide `compile_flags.txt` (or `compile_commands.json`) at the LSP root
  and a project-local `.asm-lsp.toml` naming the cross compiler. For the
  CH32V003 projects, for example:

  ```toml
  # .asm-lsp.toml in the project root
  [default_config]
  assembler = "gas"
  instruction_set = "riscv"

  [default_config.opts]
  compiler = "riscv-none-elf-gcc"
  ```

  ```text
  # compile_flags.txt in the project root
  -march=rv32ec
  -mabi=ilp32e
  -c
  -o
  /dev/null
  ```

  A project-local `.asm-lsp.toml` replaces the global config, so repeat
  `assembler`/`instruction_set` there. Without `compiler`, asm-lsp falls back
  to the host `gcc`/`clang` when applying `compile_flags.txt`, which
  mis-reports RISC-V instructions.
