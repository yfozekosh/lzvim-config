# Project Symbol Completion for Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete project-wide asm labels and C functions/globals in `.s`/`.S` buffers from the linked ELF.

**Architecture:** A new `lua/asm_symbols/` module provides a blink.cmp source that finds the newest project ELF (reusing `disasm.config.find_elf`), runs the matching `nm`, parses its symbols, and caches completion items by ELF path + mtime. It is registered as a separate provider next to `riscv_asm`.

**Tech Stack:** Neovim 0.12 Lua, `vim.system`, `vim.uv.fs_stat`, GNU binutils `nm`, blink.cmp source API, existing plain-Lua test harness.

**Spec:** `docs/superpowers/specs/2026-11-06-asm-project-symbols-design.md`

## Global Constraints

- Neovim 0.12 APIs only (`vim.system`, `vim.uv`), no new plugins or external Lua dependencies.
- Never block the editor: `nm` runs asynchronously via `vim.system` with a callback.
- Completion must not notify on every keystroke; missing ELF/nm yields empty items silently.
- Returned items must be deep-copied because blink.cmp mutates them.
- Project docs stay in sync: `README.md` and `docs/asm.md` describe the feature.
- Tests run headlessly: `nvim --headless -u NONE -l tests/asm_symbols/run.lua` from the repo root.

## Review Focus

- Auto-brackets would insert `()` after a `Function` item; asm must block auto-brackets and insert the bare symbol name.
- Symbol names may contain `$` and `.` (`__global_pointer$`); they must parse and insert unchanged.
- A missing ELF or `nm` must produce empty completions without errors or repeated notifications.
- Multiple candidate ELFs and `vim.g.asm_symbols.elf` overrides must select the intended file.
- A rebuild must invalidate the cache through the ELF mtime, without a Neovim restart.

---

### Task 1: nm parsing and completion item mapping

**Files:**
- Create: `lua/asm_symbols/init.lua`
- Create: `tests/asm_symbols/run.lua`
- Add: `docs/superpowers/specs/2026-11-06-asm-project-symbols-design.md`, `docs/superpowers/plans/2026-11-06-asm-project-symbols.md`

**Interfaces:**
- Produces: `M.parse_nm(output: string) -> Symbol[]`, where `Symbol = { name: string, type: string, address: string, size: integer|nil }`.
- Produces: `M.to_items(symbols: Symbol[], elf: string) -> lsp.CompletionItem[]`, deduplicated by name, first occurrence wins.
- Produces: `M.kind_for(symbol_type: string) -> integer` (exposed for tests).

- [ ] **Step 1: Write the failing test file**

Create `tests/asm_symbols/run.lua` with the same `eq`/`ok`/`test` harness as `tests/disasm/run.lua`, prepending this repo to `package.path`, then `local symbols = require("asm_symbols")`. Add these cases:

```lua
test("parse posix nm output", function()
  local out = table.concat({
    "delay T 9a",
    "lool T c8 4",
    "CLOCK_SPEED D 20000000",
    "_sidata A e8",
    "__global_pointer$ D 20000010",
    "",
  }, "\n")
  local parsed = symbols.parse_nm(out)
  eq(#parsed, 5)
  eq(parsed[1], { name = "delay", type = "T", address = "9a" })
  eq(parsed[2], { name = "lool", type = "T", address = "c8", size = 4 })
  eq(parsed[4], { name = "_sidata", type = "A", address = "e8" })
  eq(parsed[5].name, "__global_pointer$")
end)

test("parse skips blank, undefined and malformed lines", function()
  local out = "foo U\n\n???\nbar T 10\n"
  local parsed = symbols.parse_nm(out)
  eq(#parsed, 1)
  eq(parsed[1].name, "bar")
end)

test("item kinds follow nm types", function()
  local kind = symbols.kind_for
  eq(kind("T"), vim.lsp.protocol.CompletionItemKind.Function)
  eq(kind("w"), vim.lsp.protocol.CompletionItemKind.Function)
  eq(kind("d"), vim.lsp.protocol.CompletionItemKind.Variable)
  eq(kind("A"), vim.lsp.protocol.CompletionItemKind.Constant)
  eq(kind("?"), vim.lsp.protocol.CompletionItemKind.Text)
end)

test("to_items dedupes and inserts plain names", function()
  local items = symbols.to_items({
    { name = "delay", type = "T", address = "9a" },
    { name = "delay", type = "t", address = "aa" },
    { name = "CLOCK_SPEED", type = "D", address = "20000000" },
  }, "/proj/out/firmware.elf")
  eq(#items, 2)
  eq(items[1].label, "delay")
  eq(items[1].kind, vim.lsp.protocol.CompletionItemKind.Function)
  eq(items[1].insertText, "delay")
  eq(items[1].insertTextFormat, vim.lsp.protocol.InsertTextFormat.PlainText)
  ok(items[1].detail:find("T", 1, true) ~= nil, "detail mentions the nm type")
  ok(items[1].detail:find("0x9a", 1, true) ~= nil, "detail mentions the address")
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/yfozekosh/.config/nvim && nvim --headless -u NONE -l tests/asm_symbols/run.lua`
Expected: FAIL loading `asm_symbols` (`module 'asm_symbols' not found`).

- [ ] **Step 3: Implement parsing and item mapping**

Create `lua/asm_symbols/init.lua` with:

- `local NM_TYPES` mapping `T/W` → Function, `D/B/G/S/C/R/V` → Variable, `A` → Constant, everything else → Text. Use `vim.lsp.protocol.CompletionItemKind`.
- `M.parse_nm(output)` matching `^(%S+)%s+(%S)%s+(%x+)(%s+(%x+))?$`, skipping type `U`, blank and non-matching lines, converting size with `tonumber(size, 16)`.
- `M.to_items(symbols, elf)` building `label`/`filterText`/`insertText` = name, `insertTextFormat = PlainText`, `kind = M.kind_for(type)`, a `detail` such as `T function · 0x9a · firmware.elf`, and markdown documentation naming the ELF and address. Deduplicate with a `seen` table, first occurrence wins.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/yfozekosh/.config/nvim && nvim --headless -u NONE -l tests/asm_symbols/run.lua`
Expected: `4/4 passed`.

- [ ] **Step 5: Commit**

```bash
git add lua/asm_symbols/init.lua tests/asm_symbols/run.lua docs/superpowers/specs/2026-11-06-asm-project-symbols-design.md docs/superpowers/plans/2026-11-06-asm-project-symbols.md
git commit -m "feat(asm): parse project symbol tables for completion"
```

---

### Task 2: ELF discovery, nm resolution and async blink source

**Files:**
- Modify: `lua/asm_symbols/init.lua`
- Modify: `tests/asm_symbols/run.lua`

**Interfaces:**
- Produces: `M.resolve_nm(configured: string|string[]|nil) -> string[]|nil, string[]` (argv, candidates).
- Produces: `M.find_newest_elf(start_path: string, configured: string|nil) -> string|nil`; uses `require("disasm.config").find_elf({ elf = configured }, start_path)` and picks the greatest `mtime.sec`/`mtime.nsec`.
- Produces: `M.new(opts: table|nil) -> source` with `source:enabled()` and `source:get_completions(ctx, callback)`; also `M.doctor_lines(bufnr) -> string[]`.
- Consumes: `M.parse_nm`, `M.to_items` from Task 1.

- [ ] **Step 1: Add failing discovery tests**

Append to `tests/asm_symbols/run.lua`:

```lua
test("newest ELF wins", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/old.elf")
  vim.fn.writefile({ "" }, tmp .. "/out/new.elf")
  local old, new = tmp .. "/out/old.elf", tmp .. "/out/new.elf"
  vim.uv.fs_utime(old, 1000, 1000)
  vim.uv.fs_utime(new, 2000, 2000)
  eq(symbols.find_newest_elf(tmp .. "/src/main.s", nil), vim.fs.normalize(new))
  vim.fn.delete(tmp, "rf")
end)

test("configured ELF overrides newest", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/old.elf")
  vim.fn.writefile({ "" }, tmp .. "/out/new.elf")
  vim.uv.fs_utime(tmp .. "/out/old.elf", 1000, 1000)
  vim.uv.fs_utime(tmp .. "/out/new.elf", 2000, 2000)
  eq(
    symbols.find_newest_elf(tmp .. "/src/main.s", tmp .. "/out/old.elf"),
    vim.fs.normalize(tmp .. "/out/old.elf")
  )
  vim.fn.delete(tmp, "rf")
end)

test("resolve_nm honors an explicit executable and rejects a missing one", function()
  local argv = symbols.resolve_nm("nm")
  eq(argv, { "nm" })
  eq(symbols.resolve_nm("definitely-not-an-nm"), nil)
end)

test("no ELF yields an empty completion list", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/main.s")
  local called
  symbols.new({}).get_completions({ bufnr = buf }, function(result)
    called = result
  end)
  eq(called, { items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)

test("missing nm yields an empty completion list", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/out", "p")
  vim.fn.writefile({ "" }, tmp .. "/Makefile")
  vim.fn.writefile({ "" }, tmp .. "/out/f.elf")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. "/main.s")
  local called
  symbols.new({ nm = "definitely-not-an-nm" }).get_completions({ bufnr = buf }, function(result)
    called = result
  end)
  eq(called, { items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(tmp, "rf")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nvim --headless -u NONE -l tests/asm_symbols/run.lua`
Expected: FAIL because `find_newest_elf`, `resolve_nm` and `new` are not defined.

- [ ] **Step 3: Implement discovery and the source**

In `lua/asm_symbols/init.lua`:

- `NM_CANDIDATES = { "riscv-none-elf-nm", "riscv64-unknown-elf-nm", "riscv32-unknown-elf-nm", "nm" }`; `resolve_nm` mirrors `disasm.config.resolve_objdump`.
- `find_newest_elf` stats every candidate and returns the one with the lexicographically greatest `sec:nsec` key; missing files are skipped.
- Module-level `cache = { key, elf, items, pending }`; key is `elf .. "\0" .. sec .. ":" .. nsec`.
- `source:get_completions` resolves the buffer name (fallback `vim.fn.getcwd()`), reads `vim.g.asm_symbols` (`elf`, `nm`; `opts` overrides), and returns empty items when no ELF or nm exists.
- On a cache hit call `callback` synchronously with `vim.deepcopy(cache.items)`. On an ELF present with a new mtime, return the stale items and start a background refresh. With no cache, run `vim.system({ nm, "--defined-only", "-S", "--format=posix", elf }, { text = true }, cb)` and call `callback` from `vim.schedule`; coalesce concurrent requests for the same key so only one `nm` runs.
- `source:enabled()` returns `vim.bo.filetype == "asm"`.
- `M.new(opts)` returns the source object; `M.doctor_lines(bufnr)` returns one `INFO` line with the chosen ELF, nm path and symbol count, or an `INFO` line explaining that no ELF was found. Run nm synchronously with `:wait()` there (manual command, not completion).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nvim --headless -u NONE -l tests/asm_symbols/run.lua`
Expected: `9/9 passed` (or the exact total printed), no errors.

- [ ] **Step 5: Commit**

```bash
git add lua/asm_symbols/init.lua tests/asm_symbols/run.lua
git commit -m "feat(asm): index project symbols from the built ELF"
```

---

### Task 3: blink wiring, doctor output and docs

**Files:**
- Modify: `lua/plugins/asm.lua`
- Modify: `lua/riscv_asm/init.lua:389-500`
- Modify: `docs/asm.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `require("asm_symbols").new()` as a blink source module and `doctor_lines(bufnr)`.
- Produces: provider id `asm_symbols`, added to `sources.per_filetype.asm`; auto-brackets blocked for `asm`.

- [ ] **Step 1: Register the blink provider**

In `lua/plugins/asm.lua`'s blink spec add:

```lua
completion = {
  accept = { auto_brackets = { blocked_filetypes = { "asm" } } },
},
sources = {
  per_filetype = {
    asm = { "riscv_asm", "asm_symbols", inherit_defaults = true },
  },
  providers = {
    riscv_asm = { name = "RISC-V", module = "riscv_asm", score_offset = 10 },
    asm_symbols = { name = "ELF symbols", module = "asm_symbols", score_offset = 5 },
  },
},
```

Update the file header comment with a bullet for project symbols.

- [ ] **Step 2: Add doctor output**

In `lua/riscv_asm/init.lua` at the end of `M.doctor()` (before the final note/notify), append:

```lua
table.insert(lines, "")
vim.list_extend(lines, require("asm_symbols").doctor_lines(bufnr))
```

- [ ] **Step 3: Document the feature**

Add a "Project symbols (after build)" section to `docs/asm.md` after the RISC-V LSP subsection: newest ELF discovery, `nm` candidates, `vim.g.asm_symbols.elf`/`.nm` overrides, cache/rebuild behavior, and the limits (no `#define`/`.equ`, symbols appear only after a successful link, auto-brackets disabled). Add one sentence to the README "Assembly & linker scripts" paragraph pointing at it.

- [ ] **Step 4: Run the test suites and a config smoke test**

Run:

```bash
nvim --headless -u NONE -l tests/asm_symbols/run.lua
nvim --headless -u NONE -l tests/disasm/run.lua
nvim --headless -u NONE -c "set rtp+=/home/yfozekosh/.config/nvim" -c "lua require('asm_symbols')" -c "qa!"
```

Expected: all tests pass and the module loads without error.

- [ ] **Step 5: Manual check in the real project**

Open `~/Projects/mtrx_asm/src/boot.s` (or run headless with cwd set there), trigger completion, and confirm `delay`, `_start`, `lool`, `main1` appear; accepting `delay` inserts `delay`, not `delay()`. Run `:Build`, add a new global label, rebuild, and confirm it appears without restarting Neovim.

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/asm.lua lua/riscv_asm/init.lua docs/asm.md README.md
git commit -m "feat(asm): complete project symbols in asm buffers"
```
