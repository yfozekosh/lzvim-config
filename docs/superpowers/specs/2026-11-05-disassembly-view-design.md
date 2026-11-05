# Disassembly view with C-line mapping — design

Date: 2026-11-05
Status: proposed

## Intent

When reading C for the RISC-V firmware in
`~/Projects/riskv_asm/t1`, I want to see what the compiler actually emitted
for the line under my cursor, using the ELF that was really built — not a
Godbolt-style recompile.

The view is a vertical split: C source on the left, disassembly of the
actual ELF on the right. Moving the cursor in the source highlights every
instruction row that the ELF's debug line table attributes to that source
line.

## Goals

- Open a split showing `objdump -d -l -C` output for a real ELF.
- Parse the ELF's own line markers (`path:line`) and build a
  `(absolute source path, line) -> instruction rows` index.
- On `CursorMoved` in a mapped source buffer, highlight all matching
  instruction rows in the asm split.
- Scroll/center the asm split on the first match so the highlight is
  visible (configurable).
- Work for any source file recorded in the ELF, including `.s` files.
- Reuse the existing `asm` tree-sitter parser for highlighting and the
  existing `riscv_asm` hover/completion in the asm buffer.
- Fail with clear, actionable messages when the toolchain, ELF, or debug
  info is missing.

## Non-goals

- Reverse sync (asm cursor -> source highlight). Cursor in the asm split
  does not drive the source in v1.
- Building the firmware. `:DisasmRefresh` reruns `objdump`; it does not run
  `make`.
- Interleaving source text into the asm buffer (`objdump -S`). The C is
  already visible in the left split.
- Debugging, stepping, register/memory inspection, or a DAP integration.
- Multi-architecture abstractions beyond "GNU objdump with `-l`".
- Parsing DWARF ourselves or adding a Lua DWARF dependency.

## Approaches considered

1. **Fork `splitasm.nvim`.** Reuse its split lifecycle, line-marker parser,
   path remapping, and tests; patch its hardcoded `objdump -Mintel`, add
   extmark highlighting. Small diff, but inherits an x86-oriented codebase
   and a fork to maintain.
2. **Use `splitasm.nvim` unmodified plus a shim.** Wrapper `objdump` strips
   `-Mintel`, a local module reads splitasm internals for highlighting.
   Less code, but depends on private internals and a PATH shim.
3. **Write a small plugin in this repo.** Only the needed features; full
   control; no fork. Reimplements split/refresh/path handling but has no
   upstream assumptions to fight.

**Chosen: 3.** The required behavior is narrow, and the repo already holds
local tooling (`lua/riscv_asm/`) in the same style.

## Constraints

- Neovim 0.12 in this environment; use `vim.system` and `vim.uv`.
- The disassembler is a GNU RISC-V objdump. In `t1` it is
  `riscv-none-elf-objdump` from the xPack toolchain; plain `/usr/bin/objdump`
  cannot disassemble RISC-V.
- Builds use `-Os -g`. Debug line mapping is many-to-many: a source line can
  own several disjoint instruction ranges, and one instruction can belong to
  a line other than the textually nearest one.
- The ELF is the source of truth. Source newer than the ELF means the map may
  be stale; warn but still show it.
- Repo conventions: keep `README.md` as the source of truth for new tools,
  and `docs/README.md` as the docs index. No setup.sh migration is needed.

## Behaviour

### Opening

- `:DisasmOpen [elf]` opens a right-hand vertical split with the
  disassembly, then returns focus to the source window.
- ELF resolution order: explicit argument, `opts.elf`, then search from the
  current buffer's project root (`.git`, `Makefile`, `link.ld`) for
  `out/*.elf`, `build/*.elf`, `*.elf`. If several remain, `vim.ui.select`.
- Objdump resolution order: `opts.objdump` (string or argv table), then
  `riscv-none-elf-objdump`, `riscv64-unknown-elf-objdump`,
  `riscv32-unknown-elf-objdump`, `objdump`.
- Default args: `-d -l -C --no-show-raw-insn`.
- If a split is already open, `:DisasmOpen` refreshes it instead of creating
  a second one.

### Commands and keys

- `:DisasmOpen [elf]` — open/refresh.
- `:DisasmClose` — close the asm window.
- `:DisasmToggle [elf]` — open or close.
- `:DisasmRefresh` — rerun objdump, rebuild the index, reapply the current
  highlight.
- In the asm buffer: `q` closes the split, `r` refreshes.

No global keymap is added; the commands are enough until a preferred mapping
is chosen.

### Highlighting

- A dedicated namespace holds `line_hl_group` extmarks over each matching
  row. Default group `DisasmMatch` links to `Visual`; configurable via
  `opts.highlight`.
- The module remembers the source window that spawned the view. Only
  `CursorMoved` / `BufEnter` events in that window update the highlight.
  Focusing the asm split, help, a terminal, or a floating window does not
  clear it. Switching the source window to another file that appears in the
  ELF works automatically; switching it to an unmapped buffer clears the
  highlight.
- On a mapped source line: clear the namespace, look up `(path, line)`.
  - Hits: highlight all ranges; if `auto_scroll` is true, put the asm cursor
    on the first row and `zz` without focusing the asm window.
  - Miss (comment, declaration, line with no code): clear highlights, leave
    the asm cursor and scroll position alone.
- If the source buffer is modified (`vim.bo.modified`), still map, but warn
  once per buffer that the line numbers may have moved since the last build.
- The asm window has `cursorline = true` so the chosen first match is also
  visible as the asm cursor line.
- Highlighting never moves the source cursor and never writes to either
  buffer.

### Asm buffer

- `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, `buflisted=false`,
  `modifiable=false`.
- `filetype=asm`; start the `asm` tree-sitter parser explicitly if available.
- Diagnostics are disabled for this buffer (`vim.diagnostic.enable(false,
  { bufnr = buf })`) so asm-lsp does not compile the listing and flood it.
  The LSP client may still attach for hover; `K` is bound directly to
  `require("riscv_asm").hover_current()` so the local pseudo/register/CSR
  docs always work regardless of attach.
- Line numbers on, relative numbers off, sign column off.
- Optional winbar with the ELF basename, `Disassembly`, and `[modified]`
  when the tracked source buffer has unsaved changes.
- Source marker lines are removed from the display. Section headers, blank
  lines, and `symbol():` / `00000000 <symbol>:` headers are kept.

## Parsing

Input is the raw `objdump` stdout. Iterate once:

- **Source marker:** `^%s*(.-):(%d+)(.*)$`, where the path part looks like a
  path (absolute, drive letter, or contains `/`). Trailing
  `(discriminator N)` is ignored.
- **Instruction:** `^%s*([0-9a-fA-F]+):%s+(.*)$`; capture address and text.
- **Function header:** `^%x+ <(.+)>:$` and `^%S+%(%):$`; keep, not mapped.
- **Section header / other:** keep (section headers, blank lines).

The current source marker is **cleared** on a function or section header.
Instructions that follow an unmarked function are therefore unmapped rather
than silently attributed to the previous function's last line. This matters
for ELFs that mix objects built with and without `-g`.

For each instruction, append its display row to the current marker's
`(file, line)` entry. Consecutive rows merge into one range; a later marker
for the same `(file, line)` opens an additional range. The result:

```lua
{
  [absolute_path] = {
    [line] = { first_row = 12, ranges = { {12, 14}, {40, 40} } },
  },
}
```

Path normalization: `vim.fs.normalize`, forward slashes, absolute paths. A
relative marker path is resolved against, in order, the ELF's project root,
the ELF directory, and the current working directory; the first existing
file wins. Roots are computed once when the index is built and come from the
ELF, never from whichever source buffer happened to open the view. Buffer
paths are normalized the same way for lookup.

The parser is pure and does no filesystem access. It receives an injected
`resolve_path(raw)` callback (implemented in `config.lua` with
`vim.uv.fs_stat`) plus the display/selection options. No window or buffer
calls either, so every case, including relative paths, can be tested
headlessly with fixtures and a fake resolver.

## Toolchain and errors

- Missing objdump: notify with the candidates tried and an `opts.objdump`
  example.
- Nonzero exit: notify stderr, do not open an empty split.
- ELF without `.debug_line` (no markers): show the disassembly, notify once
  that line mapping is unavailable.
- Source file newer than the ELF: on open/refresh, stat every file in the
  index and notify once if any is newer, suggesting a rebuild. Still show
  the mapping.
- A mapped source buffer is modified: map anyway, but warn once per buffer
  and show `[modified]` in the winbar; mtime cannot catch unsaved edits.
- ELF not found: notify with the directories searched and how to pass a path.

## Files

```
plugin/disasm.lua              -- user commands; requires lua/disasm lazily
lua/disasm/init.lua            -- setup, state, open/close/toggle/refresh
lua/disasm/config.lua          -- defaults, normalization, ELF/objdump resolution
lua/disasm/parser.lua          -- pure objdump parsing and index building
lua/disasm/view.lua            -- split, buffer, extmarks, cursor/scroll
lua/disasm/health.lua          -- optional :checkhealth disasm
tests/disasm/run.lua           -- headless assert-based test runner
tests/disasm/fixtures/*.txt    -- captured objdump output, incl. RISC-V cases
```

`plugin/disasm.lua` is loaded by Neovim from the config's runtimepath; it
only registers commands and requires the module on first use.

## Configuration

```lua
require("disasm").setup({
  objdump = nil,          -- string or argv table; nil = auto-detect
  elf = nil,              -- string or function returning a path
  args = { "-d", "-l", "-C", "--no-show-raw-insn" },
  auto_scroll = true,
  highlight = "Visual",   -- group linked to DisasmMatch
  winbar = true,
})
```

Defaults are set in `config.lua`; `plugin/disasm.lua` calls
`setup(vim.g.disasm or {})` so commands work without user configuration.
Users set `vim.g.disasm` (for example in `lua/config/options.lua`).

## Tests

- Parser unit tests with captured fixtures:
  - RISC-V compressed and 32-bit instructions, 0-based addresses.
  - `(discriminator N)` markers.
  - Same source line appearing in two disjoint places.
  - Multiple source files, absolute and relative paths.
  - Function headers, section headers, blank lines.
  - A function with no markers after a marked function (must stay unmapped).
  - No debug markers at all.
- Run with `nvim --headless -u NONE -l tests/disasm/run.lua`.
- Manual check in `t1`: open `src/test.c`, `:DisasmOpen` (auto-detects
  `out/firmware.elf`), verify:
  - line 6 -> prologue rows,
  - line 8 -> `li s0,0`,
  - line 13 -> both the `lui/lw` group and the `lw a0,0(a5)` / `jal delay`
    group,
  - line 10 -> the `j` at the end,
  - line 11 (a comment) -> no highlight.
- Also verify a `.s` file (`src/delay.s`) maps.

## Documentation

- Add a "Disassembly view" section to `README.md` (what it is, commands,
  configuration).
- Add `docs/disasm.md` with the detailed behavior and limitations; link it
  from `docs/README.md`.

## What is left to the builder

- Exact av/asynchronous process choice (`vim.system` callback vs blocking)
  and how the loading state is shown.
- Internal helper names and whether state lives in one module or a small
  state table.
- Winbar/statusline rendering details and default highlight aesthetics.
- Whether to add `:checkhealth disasm`.
- Test fixture contents beyond the cases listed above.
