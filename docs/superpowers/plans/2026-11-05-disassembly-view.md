# Disassembly View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Neovim plugin that opens a split with real `objdump` disassembly of the project ELF and highlights every instruction belonging to the C line under the cursor.

**Architecture:** A pure parser turns `objdump -d -l -C` output into display lines plus a `path -> line -> row ranges` index. A view module owns the split, buffer, extmarks, and scrolling. An init module wires ELF/objdump resolution, commands, and cursor autocmds. Commands are registered from `plugin/disasm.lua`.

**Tech Stack:** Neovim 0.12 Lua, `vim.system`, `vim.uv`, `vim.api` extmarks, tree-sitter `asm` parser.

**Spec:** `docs/superpowers/specs/2026-11-05-disassembly-view-design.md`

## Global Constraints

- Neovim 0.12 (`vim.system`, `vim.diagnostic.enable(false, { bufnr = ... })`).
- GNU objdump with `-l`; default args `-d -l -C --no-show-raw-insn`.
- Toolchain candidates in order: configured `objdump`, `riscv-none-elf-objdump`, `riscv64-unknown-elf-objdump`, `riscv32-unknown-elf-objdump`, `objdump`.
- No new dependencies, no setup.sh migration.
- Parser does no filesystem access; path resolution is injected.
- Source paths and buffer paths are normalized with `vim.fs.normalize`.
- Update `README.md` and `docs/disasm.md` / `docs/README.md` in the same change.

## Review Focus

- Focusing the asm split must not clear the highlight; only the tracked source window updates it.
- An unmarked function must not inherit the previous source marker.
- Relative and absolute marker paths, and buffer paths, must normalize to the same key.
- Missing `-l` markers or a failing objdump must notify and not leave a half-open empty view.
- `-Os` can map one line to several disjoint ranges; all of them must highlight.

---

### Task 1: Pure parser and line index

**Files:**
- Create: `lua/disasm/parser.lua`
- Create: `tests/disasm/run.lua`
- Create: `tests/disasm/fixtures/riscv_objdump.txt`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```lua
  --- @class DisasmEntry
  --- @field first_row integer
  --- @field ranges integer[][]  -- 1-based inclusive {start_row, end_row}

  --- @param asm_lines string[]
  --- @param opts { resolve_path: fun(raw: string): string? }
  --- @return { lines: string[], index: table<string, table<integer, DisasmEntry>>, has_markers: boolean }
  function M.parse(asm_lines, opts)
  ```

- [ ] **Step 1: Write the fixture and failing tests**

Fixture `tests/disasm/fixtures/riscv_objdump.txt`:

```text
out/firmware.elf:     file format elf32-littleriscv

Disassembly of section .text:

00000000 <_start>:
_start():
/home/proj/src/boot.s:13
   0:	auipc	sp,0x20001
   4:	addi	sp,sp,-2048
/home/proj/src/boot.s:17
   8:	lui	t0,0x40021

0000009a <main>:
main():
/home/proj/src/test.c:6
  9a:	addi	sp,sp,-8
  9c:	sw	s0,0(sp)
/home/proj/src/test.c:13 (discriminator 2)
  a2:	lui	a5,0x20000
  a6:	lw	a5,0(a5)
/home/proj/src/test.c:12
  aa:	addi	s0,s0,1
/home/proj/src/test.c:13 (discriminator 2)
  ac:	lw	a0,0(a5)
  ae:	jal	b2 <delay>
/home/proj/src/test.c:10
  b0:	j	a2 <main+0x8>

000000b2 <delay>:
delay():
/home/proj/src/delay.s:7
  b2:	blez	a0,bc <delay+0xa>
/home/proj/src/delay.s:10
  b6:	addi	a0,a0,-4
/home/proj/src/delay.s:11
  b8:	bgtz	a0,b6 <delay+0x4>
/home/proj/src/delay.s:14
  bc:	ret

000000be <no_debug>:
  be:	nop
  c0:	ret
```

Test runner `tests/disasm/run.lua` sets the module path, defines `eq`, and runs:

- `test_parses_markers_and_rows`: markers are removed; `boot.s:13` has `first_row == 5`; `test.c:13` has two ranges and `first_row` is the `lui` row.
- `test_disjoint_ranges`: `test.c:13` ranges are `{{17,18},{21,22}}` (verify against the fixture; adjust only if the fixture rows are changed).
- `test_unmarked_function_stays_unmapped`: no index entry contains rows `29` or `30` (`no_debug`).
- `test_no_markers`: parsing a plain disassembly returns `has_markers == false` and an empty index.
- `test_relative_path_is_resolved`: pass `resolve_path = function(p) return "/abs/" .. p end` and assert the key is `/abs/src/test.c`.
- `test_function_and_section_headers_are_kept`: display lines include `0000009a <main>:`, `main():`, and `Disassembly of section .text:`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `nvim --headless -u NONE -l tests/disasm/run.lua`
Expected: FAIL because `disasm.parser` cannot be loaded.

- [ ] **Step 3: Implement `lua/disasm/parser.lua`**

Rules:
- Source marker: `^%s*(.-):(%d+)` where the captured path is absolute, has a drive letter, or contains `/` or `\`. Do not display marker lines. Reset the marker after parsing it.
- Instruction: `^%s*([0-9a-fA-F]+):%s+`. Display the raw line and append its row to the current marker entry.
- Consecutive instruction rows extend the last range; a later marker for the same `(path, line)` appends a new range.
- Function headers `^%x+ <.+>:$`, `^%S+%(%):$`, and `Disassembly of section` are displayed and clear the current marker.
- All other lines are displayed unchanged.
- Resolve each marker path once through `opts.resolve_path(raw) or vim.fs.normalize(raw)`.
- Return `first_row` as the first instruction row for that `(path, line)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `nvim --headless -u NONE -l tests/disasm/run.lua`
Expected: `ok` lines for every test and exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lua/disasm/parser.lua tests/disasm
git commit -m "feat(disasm): parse objdump line markers into a row index"
```

---

### Task 2: Config, ELF/objdump resolution, path resolver

**Files:**
- Create: `lua/disasm/config.lua`
- Modify: `tests/disasm/run.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```lua
  function M.setup(user_opts) -> config
  function M.resolve_objdump(config) -> string[]|nil, string[]  -- argv, candidates
  function M.find_elf(config, start_path) -> string[]          -- candidate paths
  function M.make_path_resolver(elf_path) -> fun(raw: string): string?
  function M.roots_for(elf_path) -> { project: string, elf_dir: string, cwd: string }
  ```

- [ ] **Step 1: Write failing tests**

Add to `tests/disasm/run.lua`:
- `test_defaults`: `setup({}).args` equals `{ "-d", "-l", "-C", "--no-show-raw-insn" }` and `auto_scroll == true`.
- `test_string_objdump`: `resolve_objdump(setup({ objdump = "cat" }))` returns `{ "cat" }`.
- `test_table_objdump`: `resolve_objdump(setup({ objdump = { "sh", "-c" } }))` returns `{ "sh", "-c" }`.
- `test_resolver_absolute`: with a temp file created via `vim.fn.tempname()`, `make_path_resolver` returns the normalized absolute path.
- `test_resolver_relative`: create `<temp>/src/x.c`, build ELF path `<temp>/out/f.elf` (file need not exist) and assert `make_path_resolver` resolves `src/x.c` to `<temp>/src/x.c`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `nvim --headless -u NONE -l tests/disasm/run.lua`
Expected: FAIL because `disasm.config` cannot be loaded.

- [ ] **Step 3: Implement `lua/disasm/config.lua`**

- Merge defaults with `user_opts`.
- `resolve_objdump`: accept a string or argv table; otherwise try the candidate list with `vim.fn.executable`. Return the argv and the candidate list (for error messages).
- `find_elf`: explicit `config.elf` (string or function) first; otherwise walk up from the start path for `.git`, `Makefile`, `link.ld`; glob `out/*.elf`, `build/*.elf`, `*.elf`; dedupe and sort.
- `roots_for`: project root from `vim.fs.root(elf, markers)` or the ELF directory; plus ELF directory and `cwd`.
- `make_path_resolver`: absolute paths returned normalized if they exist, otherwise normalized as-is; relative paths tried against project, ELF dir, and cwd, first existing wins, fallback `project/raw`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `nvim --headless -u NONE -l tests/disasm/run.lua`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/disasm/config.lua tests/disasm/run.lua
git commit -m "feat(disasm): resolve toolchain, ELF, and marker paths"
```

---

### Task 3: Split, highlight, commands, autocmds

**Files:**
- Create: `lua/disasm/view.lua`
- Create: `lua/disasm/init.lua`
- Create: `plugin/disasm.lua`

**Interfaces:**
- Consumes: `parser.parse`, `config.setup/resolve_objdump/find_elf/make_path_resolver`.
- Produces:
  ```lua
  -- view.lua
  function M.define_highlight(config)
  function M.open(state) -> boolean
  function M.render(state) -> boolean
  function M.highlight(state, ranges)
  function M.clear(state)
  function M.scroll_to(state, row)
  function M.set_winbar(state)
  function M.close(state)

  -- init.lua
  function M.setup(opts)
  function M.open(elf)
  function M.close()
  function M.toggle(elf)
  function M.refresh()
  ```

- [ ] **Step 1: Implement `lua/disasm/view.lua`**

- `define_highlight`: `DisasmMatch` defaults to `{ link = config.highlight }`.
- `open`: reuse `state.asm_win` if valid; otherwise split right of `state.source_win` and restore focus. Set buffer options (`nofile`, `bufhidden=wipe`, `swapfile=false`, `buflisted=false`, `modifiable=false` after rendering), window options (`number`, `cursorline`, `signcolumn=no`, `foldcolumn=0`, `wrap=false`).
- `render`: set lines, `filetype=asm`, `vim.treesitter.start(buf, "asm")`, `vim.diagnostic.enable(false, { bufnr = buf })`, then read-only. Render is called after `state.lines` and `state.elf` are set.
- `highlight`: clear namespace, then one extmark per row in each range with `line_hl_group = "DisasmMatch"`, `priority = 200`.
- `scroll_to`: set asm cursor and `zz` via `nvim_win_call`.
- Buffer keymaps: `q` close, `r` refresh, `K` `require("riscv_asm").hover_current()`.

- [ ] **Step 2: Implement `lua/disasm/init.lua`**

- `setup`: normalize config, create namespace and augroup, define highlight.
- `run_objdump(elf)`: `vim.system(argv .. args .. { elf }, { text = true }):wait()`; on nonzero code notify stderr and return nil.
- `open(elf)`: remember the source window, resolve ELF (if multiple, `vim.ui.select` and continue), resolve objdump, run it, parse with `config.make_path_resolver(elf)`, store `lines/index/has_markers/elf`, open and render, warn once if no markers, run the staleness check, update highlight.
- `update_highlight`: only when current window is `state.source_win`; look up normalized buffer path and cursor line; clear on miss; highlight all ranges and scroll to `first_row` when `auto_scroll`; warn once per modified buffer.
- Autocmds in group `Disasm`: `CursorMoved`, `BufEnter`, `WinEnter` -> `update_highlight`; `BufWipeout` for the asm buffer -> clear state.
- `refresh`: rerun `open(state.elf)`.
- Staleness: stat every source path in the index; compare `mtime.sec` with the ELF; notify once with up to three names.
- `close`: close the asm window if valid, clear state.

- [ ] **Step 3: Implement `plugin/disasm.lua`**

```lua
require("disasm").setup(vim.g.disasm or {})

vim.api.nvim_create_user_command("DisasmOpen", function(o)
  require("disasm").open(o.args ~= "" and o.args or nil)
end, { nargs = "?", complete = "file", desc = "Open disassembly split" })
vim.api.nvim_create_user_command("DisasmClose", function() require("disasm").close() end, { desc = "Close disassembly split" })
vim.api.nvim_create_user_command("DisasmToggle", function(o)
  require("disasm").toggle(o.args ~= "" and o.args or nil)
end, { nargs = "?", complete = "file", desc = "Toggle disassembly split" })
vim.api.nvim_create_user_command("DisasmRefresh", function() require("disasm").refresh() end, { desc = "Refresh disassembly" })
```

- [ ] **Step 4: Headless smoke test**

Run:
```bash
nvim --headless -u NONE \
  --cmd "set rtp+=." \
  -c "lua require('disasm').setup({ objdump = { 'cat', 'tests/disasm/fixtures/riscv_objdump.txt' }, args = {}, elf = 'out/firmware.elf' }); require('disasm').open()" \
  -c "lua vim.cmd('qa!')"
```
Expected: no Lua error. (The view opens and renders the fixture through the `cat` shim.)

- [ ] **Step 5: Commit**

```bash
git add lua/disasm/view.lua lua/disasm/init.lua plugin/disasm.lua
git commit -m "feat(disasm): split view, highlighting, and commands"
```

---

### Task 4: Documentation and real-project verification

**Files:**
- Modify: `README.md`
- Create: `docs/disasm.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-11-05-disassembly-view-design.md` (config entry point note)

**Interfaces:**
- Consumes: everything above.
- Produces: user-facing docs only.

- [ ] **Step 1: Verify against the real ELF**

In `~/Projects/riskv_asm/t1`, run `make link` if needed, then from Neovim:

```bash
cd /home/yfozekosh/Projects/riskv_asm/t1
nvim src/test.c
```

Run `:DisasmOpen`. Verify:
- line 6 highlights the prologue rows,
- line 8 highlights `li s0,0`,
- line 13 highlights both the `lui`/`lw` group and the `lw a0,0(a5)` / `jal delay` group,
- line 10 highlights the final `j`,
- line 11 (comment) clears the highlight,
- `Ctrl-w l` to the asm split keeps the highlight,
- `:DisasmRefresh` after `make link` updates the view.

Also open `src/delay.s` and confirm its lines map.

- [ ] **Step 2: Write `docs/disasm.md`**

Cover purpose, commands, configuration (`vim.g.disasm`), how line mapping works from `objdump -l`, limitations (stale builds, unsaved edits, optimized many-to-many mapping), and the `t1` usage example.

- [ ] **Step 3: Update `README.md` and `docs/README.md`**

Add a "Disassembly view" section to `README.md` with commands and a link to `docs/disasm.md`; add the doc to the index in `docs/README.md`.

- [ ] **Step 4: Run the full test suite and a Lua syntax check**

Run:
```bash
nvim --headless -u NONE -l tests/disasm/run.lua
luac -p lua/disasm/*.lua plugin/disasm.lua 2>/dev/null || true
```
Expected: tests pass; no syntax errors.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/disasm.md docs/README.md docs/superpowers/specs/2026-11-05-disassembly-view-design.md
git commit -m "docs(disasm): document the split disassembly view"
```
