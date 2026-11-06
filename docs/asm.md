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

### Diagnostics (compiler errors)

asm-lsp has no parser-based error checking: diagnostics come from running a
real compiler/assembler on the file and parsing its stderr. Neovim 0.12
requests them as pull diagnostics, so they refresh while you type rather
than only on `:w`.

By default the plugin config leaves `default_diagnostics = false`, because
falling back to the host `gcc` would reject every RISC-V mnemonic. A file
therefore gets no diagnostics until its project has an `.asm-lsp.toml` in the
LSP root that names a RISC-V `compiler` and the compile flags. A project
config replaces the global one, so repeat `assembler` and `instruction_set`.
For example, for the CH32V003 (RV32EC) assembly projects:

```toml
# .asm-lsp.toml in the project root
[default_config]
assembler = "gas"
instruction_set = "riscv"

[default_config.opts]
compiler = "riscv-none-elf-gcc"
compile_flags_txt = [
  "-march=rv32ec",
  "-mabi=ilp32e",
  "-c",
  "-o",
  "/dev/null",
]
```

`-c -o /dev/null` stops GCC from trying to link (asm-lsp only type-checks the
file); `-fsyntax-only` works too. asm-lsp also accepts flags from a
`compile_flags.txt` or `compile_commands.json` in the LSP root instead of
`compile_flags_txt`, but those files are shared with clangd: `-march=rv32ec`
without a RISC-V `--target` makes clangd fail on C files in the same tree, so
prefer `compile_flags_txt` in mixed C/asm projects.

The LSP root is the nearest directory with `.asm-lsp.toml`, `.git`,
`compile_flags.txt` or `compile_commands.json` (the database files are extra
root markers in `lua/plugins/asm.lua`). Run `:RiscvAsmDoctor` in a buffer to
see which piece is missing, which config is in effect, and whether the
compiler and flags are found. The equivalent manual check is:

```sh
riscv-none-elf-gcc -march=rv32ec -mabi=ilp32e -c -o /dev/null boot.s
```

### Formatter: rvfmt

`rvfmt` ([riscv-asm-fmt](https://github.com/mattfbacon/riscv-asm-fmt)) runs
through `conform.nvim` for the `asm` filetype, so LazyVim's format-on-save
and `<leader>cf` both work. `setup.sh` builds it from a pinned commit with
`patches/riscv-asm-fmt-dollar-symbol.patch`, because upstream's lexer rejects
`$` in identifiers and therefore fails on the standard `__global_pointer$`
linker symbol.

## Project symbols (after build)

asm-lsp has no project index, so labels defined in other `.s`/`.S` files and
functions/globals from C never appear in its completion. `lua/asm_symbols/`
adds a separate blink.cmp source (`asm_symbols`, filetype `asm`) that reads
the project's newest linked ELF with `nm`:

- ELF discovery reuses the disassembly view's roots and patterns
  (`out/*.elf`, `build/*.elf`, `*.elf`); `vim.g.asm_symbols.elf` pins one.
- `nm` is resolved like objdump (`riscv-none-elf-nm` first, then host `nm`);
  override with `vim.g.asm_symbols.nm`.
- Items are cached by ELF path + mtime, so a `<leader>cb` rebuild is picked
  up on the next completion without restarting Neovim. `nm` runs
  asynchronously, so completion never blocks.
- `T`/`W` become functions, data/bss objects become variables, absolute
  symbols become constants. Auto-brackets are disabled for `asm`, so accepting
  `delay` inserts `delay`.

Run `:RiscvAsmDoctor` to see the chosen ELF, nm and symbol count.

Limits: symbols only exist after a successful link; C macros and asm `.equ`
constants are not ELF symbols and are not completed; assembler-discarded
`.L...` labels remain handled by asm-lsp for the current file.

## Linker scripts (`ld`)

GNU ld linker scripts (filetype `ld`, see `ftdetect/linker.lua` for the extra
extensions) get tree-sitter highlighting, folding and indentation from the
`linkerscript` parser, plus a small formatter.

### Formatter: ld-format

`ld-format` (`scripts/ld-format`, symlinked to `~/.local/bin/ld-format` by
`setup.sh`) runs through `conform.nvim` for the `ld` filetype, so LazyVim's
format-on-save and `<leader>cf` both work. It is a dependency-free Python 3
helper (no Mason package) that:

- strips trailing whitespace,
- recomputes indentation from `{`/`}` nesting (2 spaces per level),
- collapses runs of blank lines to a single blank line,
- ensures the file ends with exactly one newline.

C-style comments are preserved verbatim and do not contribute to brace
counting. Only braces drive indentation, because `(` and `)` also appear in
expressions. Autoindent while typing comes from the `linkerscript`
tree-sitter indent query; if treesitter is unavailable, Neovim's built-in
`indent/ld.vim` (brace counting) is used as a fallback.

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
- If no compiler errors show up, run `:RiscvAsmDoctor`; the project needs a
  `.asm-lsp.toml` with a `compiler` and `compile_flags_txt` (or a
  `compile_flags.txt`/`compile_commands.json`) at the LSP root. See
  [Diagnostics](#diagnostics-compiler-errors).
