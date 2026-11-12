# Raspberry Pi plugin-free Neovim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Neovim start cleanly on the Raspberry Pi with a plugin-free config that mirrors the daily LazyVim feel as closely as built-ins allow.

**Architecture:** `init.lua` detects `/etc/rpi-issue` (or `YF_NVIM_MINIMAL`) and loads `config.minimal` before lazy.nvim, returning early. `config.minimal` is split into options, colors, statusline, pickers, and keymaps modules; all are plain Lua and use only Neovim 0.10-compatible APIs. The full LazyVim path is untouched for every other machine.

**Tech Stack:** Neovim 0.10.4 (Pi, Debian trixie) and 0.12.6 (dev machine), Lua, Python 3 stdlib for the setup migration guard, headless `nvim -l` tests.

**Spec:** `docs/superpowers/specs/2026-11-12-pi-minimal-nvim-design.md`

## Global Constraints

- Must run on Neovim **0.10.4** and 0.12.x; no 0.11-only APIs (`vim.diagnostic.jump`, `vim.diagnostic.count`, `vim.lsp.config`).
- No plugins, no lazy.nvim, no network access at startup on the minimal path.
- No required external binaries; `rg`, `grep`, and `lazygit` are optional (`vim.fn.executable` checks).
- Do not change behavior of the full LazyVim config when `vim.g.yf_minimal` is false.
- No file under `~/.local/share/nvim/lazy` may enter the minimal runtime path.
- Follow repo conventions: `lua/config/` modules, `tests/<area>/run.lua`, README is the source of truth, local git identity `yfozekosh <yfozekosh@gmail.com>`.
- Keep the design values exact: Nord `#2E3440` background, `#D8DEE9` foreground, `#616E88` comments, leader `" "`.

## Review Focus

- An unnamed or readonly buffer rendering the statusline: must show `[No Name]` and flags, never throw.
- No LSP clients or diagnostics (the normal Pi case): `<F11>`, `[d/]d`, and `<leader>cd` must not error on 0.10.4.
- `<F2>` on a buffer with no filetype/commentstring: must fall back to Neovim's default instead of throwing.
- File find in an empty directory or a tree full of `.git` internals: must return `{}` or exclude `.git`, never error.
- Grep pattern containing spaces or quotes: must be shell-escaped so the quickfix search does not break.

---

### Task 1: Pi detection, entry module, and options

**Files:**
- Modify: `init.lua:1-24`
- Create: `lua/config/minimal/init.lua`
- Create: `lua/config/minimal/colors.lua` (temporary no-op stub)
- Create: `lua/config/minimal/statusline.lua` (temporary no-op stub)
- Create: `lua/config/minimal/pickers.lua` (temporary no-op stub)
- Create: `lua/config/minimal/keymaps.lua` (temporary no-op stub)
- Test: `tests/minimal/run.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `require("config.minimal").enabled() -> boolean`;
  `require("config.minimal").setup() -> nil`, which sets `vim.g.mapleader`,
  all editor options, and calls the four submodule `setup()` functions.
  Each stub exports `M.setup()`.

- [ ] **Step 1: Write the failing test**

Create `tests/minimal/run.lua`:

```lua
-- Run from the repo root:
--   nvim --headless -u NONE -l tests/minimal/run.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local minimal = require("config.minimal")

-- Detection: environment override wins over the hardware marker.
vim.env.YF_NVIM_MINIMAL = "1"
assert(minimal.enabled(), "YF_NVIM_MINIMAL=1 must force the minimal config")
vim.env.YF_NVIM_MINIMAL = "0"
assert(not minimal.enabled(), "YF_NVIM_MINIMAL=0 must disable it")
vim.env.YF_NVIM_MINIMAL = nil

minimal.setup()

assert(vim.g.mapleader == " ", "leader must be space")
assert(vim.o.number and vim.o.relativenumber, "line numbers must be on")
assert(vim.o.signcolumn == "yes", "sign column must always be visible")
assert(vim.o.expandtab and vim.o.shiftwidth == 2 and vim.o.tabstop == 2, "2-space indent")
assert(vim.o.termguicolors, "true color must be on")
assert(vim.o.laststatus == 3 and vim.o.showmode == false, "global statusline")
assert(vim.o.shadafile == "NONE", "shada must be disabled")
assert(vim.fn.exists(":Lazy") == 0, "the minimal config must not define :Lazy")

print("minimal tests OK")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: FAIL with `module 'config.minimal' not found`.

- [ ] **Step 3: Implement detection, entry module, and options**

Replace the Raspberry Pi block in `init.lua` with:

```lua
-- Raspberry Pi and other explicitly minimal machines run a plugin-free
-- config: LazyVim needs Neovim >= 0.11.2, Debian trixie ships 0.10.4, and
-- the Pi has ~91 MB RAM free. YF_NVIM_MINIMAL=1/0 overrides detection.
local minimal = require("config.minimal")
if minimal.enabled() then
  vim.g.yf_minimal = true
  minimal.setup()
  return
end
```

`lua/config/minimal/init.lua`:

```lua
local M = {}

function M.enabled()
  local override = vim.env.YF_NVIM_MINIMAL
  if override == "1" then
    return true
  end
  if override == "0" then
    return false
  end
  return vim.fn.filereadable("/etc/rpi-issue") == 1
end

local function try_set(name, value)
  pcall(function()
    vim.opt[name] = value
  end)
end

function M.setup()
  vim.g.mapleader = " "
  vim.g.maplocalleader = "\\"
  vim.g.autoformat = false
  vim.g.snacks_animate = false
  vim.opt.shadafile = "NONE"
  vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
  vim.opt.autowrite = true
  vim.opt.completeopt = "menu,menuone,noselect"
  vim.opt.confirm = true
  vim.opt.cursorline = true
  vim.opt.expandtab = true
  vim.opt.fillchars = { eob = " ", fold = " ", foldopen = "+", foldclose = "-", foldsep = " ", diff = "/" }
  vim.opt.foldlevel = 99
  vim.opt.foldmethod = "indent"
  vim.opt.foldtext = ""
  vim.opt.formatoptions = "jcroqlnt"
  vim.opt.grepformat = "%f:%l:%c:%m"
  vim.opt.grepprg = vim.fn.executable("rg") == 1 and "rg --vimgrep --no-heading" or "grep -Rn"
  vim.opt.ignorecase = true
  vim.opt.inccommand = "nosplit"
  vim.opt.laststatus = 3
  vim.opt.linebreak = true
  vim.opt.list = true
  vim.opt.mouse = "a"
  vim.opt.number = true
  vim.opt.pumblend = 10
  vim.opt.pumheight = 10
  vim.opt.relativenumber = true
  vim.opt.ruler = false
  vim.opt.scrolloff = 4
  vim.opt.shiftround = true
  vim.opt.shiftwidth = 2
  vim.opt.showmode = false
  vim.opt.sidescrolloff = 8
  vim.opt.signcolumn = "yes"
  vim.opt.smartcase = true
  vim.opt.smartindent = true
  vim.opt.spelllang = "en"
  vim.opt.splitbelow = true
  vim.opt.splitkeep = "screen"
  vim.opt.splitright = true
  vim.opt.tabstop = 2
  vim.opt.termguicolors = true
  vim.opt.timeoutlen = 300
  vim.opt.undofile = true
  vim.opt.undolevels = 10000
  vim.opt.updatetime = 200
  vim.opt.virtualedit = "block"
  vim.opt.wildmode = "longest:full,full"
  vim.opt.wrap = false
  vim.opt.shortmess:append("WIcC")
  try_set("jumpoptions", "view")
  try_set("smoothscroll", true)
  try_set("winminwidth", 5)

  require("config.minimal.colors").setup()
  require("config.minimal.statusline").setup()
  require("config.minimal.pickers").setup()
  require("config.minimal.keymaps").setup()
end

return M
```

Create the four stubs, each exactly:

```lua
local M = {}

function M.setup() end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: `minimal tests OK`.

- [ ] **Step 5: Verify the real init branch**

Run:
`YF_NVIM_MINIMAL=1 nvim --headless -u NONE -c 'set rtp^=.' -c 'luafile init.lua' -c 'lua assert(vim.g.yf_minimal == true)' -c 'lua assert(vim.fn.exists(":Lazy") == 0)' -c qa`
Expected: exit code 0, no output. Then run the same command with
`YF_NVIM_MINIMAL=0` and `-c 'lua assert(vim.g.yf_minimal == nil)'`; expected
exit code 0 (the full path is not exercised with `-u NONE`).

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/config/minimal tests/minimal/run.lua
git commit -m "feat(nvim): add plugin-free config entry for Raspberry Pi"
```

---

### Task 2: Nord-like colorscheme

**Files:**
- Modify: `lua/config/minimal/colors.lua` (replace stub)
- Test: `tests/minimal/run.lua`

**Interfaces:**
- Consumes: `config.minimal.setup()` already calls `colors.setup()`.
- Produces: `require("config.minimal.colors").setup() -> nil`; sets
  `termguicolors` and all highlight groups listed below.

- [ ] **Step 1: Write the failing test**

Append to `tests/minimal/run.lua` before the final `print`:

```lua
local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end

assert(hl("Normal").fg == tonumber("D8DEE9", 16), "Nord foreground")
assert(hl("Normal").bg == tonumber("2E3440", 16), "Nord background")
assert(hl("Comment").fg == tonumber("616E88", 16), "Nord comment")
assert(hl("Visual").bg == tonumber("434C5E", 16), "Nord selection")
assert(hl("DiagnosticError").fg == tonumber("BF616A", 16), "Nord error")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: FAIL on the first color assertion.

- [ ] **Step 3: Implement `lua/config/minimal/colors.lua`**

Palette locals: `bg=#2E3440`, `bg_alt=#3B4252`, `bg_sel=#434C5E`,
`fg=#D8DEE9`, `fg_bright=#ECEFF4`, `comment=#616E88`,
`frost=#88C0D0`, `frost2=#81A1C1`, `frost3=#8FBCBB`, `blue=#5E81AC`,
`red=#BF616A`, `orange=#D08770`, `yellow=#EBCB8B`, `green=#A3BE8C`,
`purple=#B48EAD`.

`setup()` must run `vim.o.background = "dark"`, `vim.cmd("highlight clear")`,
`syntax reset` when `vim.fn.exists("syntax_on") == 1`, then set groups with
`vim.api.nvim_set_hl(0, name, opts)`:

| Groups | Foreground / background / style |
|---|---|
| `Normal`, `NormalNC` | fg / bg |
| `NormalFloat`, `FloatBorder` | fg / bg_alt, border frost2 |
| `Comment`, `SpecialComment` | comment, italic |
| `Constant`, `Number`, `Boolean`, `Float`, `Character` | purple |
| `String` | green |
| `Identifier`, `Function` | frost |
| `Statement`, `Keyword`, `Conditional`, `Repeat`, `Label`, `Operator` | frost2 |
| `PreProc`, `Include`, `Define`, `Macro`, `PreCondit` | frost2 |
| `Type`, `StorageClass`, `Structure`, `Typedef` | frost3 |
| `Special`, `SpecialChar`, `Delimiter`, `Tag` | frost |
| `Error`, `ErrorMsg`, `DiagnosticError` | red |
| `Todo` | yellow / bg_alt, bold |
| `WarningMsg`, `DiagnosticWarn` | yellow |
| `ModeMsg`, `MoreMsg`, `Question`, `Title` | frost |
| `Directory` | frost |
| `Visual`, `VisualNOS`, `PmenuSel` | bg_sel |
| `Search`, `IncSearch`, `CurSearch` | fg_bright / blue, bold |
| `MatchParen` | frost, bold, underline |
| `CursorLine`, `ColorColumn` | bg_alt |
| `CursorLineNr` | yellow, bold |
| `LineNr`, `FoldColumn`, `NonText`, `Whitespace`, `SpecialKey`, `EndOfBuffer` | comment |
| `SignColumn` | fg / bg |
| `StatusLine`, `StatusLineNC`, `WinSeparator`, `VertSplit` | fg / bg_alt |
| `StatusLineMode` | bg / frost, bold |
| `Pmenu`, `PmenuSbar` | fg / bg_alt |
| `PmenuThumb` | bg_sel |
| `Folded` | frost2 / bg_alt |
| `DiffAdd` | green / bg_alt |
| `DiffChange` | yellow / bg_alt |
| `DiffDelete` | red / bg_alt |
| `DiffText` | fg_bright / blue |
| `DiagnosticInfo` | frost |
| `DiagnosticHint` | frost3 |
| `DiagnosticVirtualTextError`, `DiagnosticVirtualTextWarn`, `DiagnosticVirtualTextInfo`, `DiagnosticVirtualTextHint` | matching Aurora/Frost colors, italic |
| `DiagnosticUnderlineError`, `DiagnosticUnderlineWarn`, `DiagnosticUnderlineInfo`, `DiagnosticUnderlineHint` | matching color, underline |
| `LspInlayHint` | comment, italic |
| `QuickFixLine` | bg_sel, bold |

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: `minimal tests OK`.

- [ ] **Step 5: Commit**

```bash
git add lua/config/minimal/colors.lua tests/minimal/run.lua
git commit -m "feat(nvim): add Nord-like highlights to minimal config"
```

---

### Task 3: Built-in status line

**Files:**
- Modify: `lua/config/minimal/statusline.lua` (replace stub)
- Test: `tests/minimal/run.lua`

**Interfaces:**
- Consumes: `colors.setup()` defines `StatusLineMode`, `DiagnosticError`, etc.
- Produces: `require("config.minimal.statusline").setup() -> nil` (sets
  `vim.o.statusline` to `%!v:lua.__yf_minimal_statusline()`);
  `.render() -> string`.

- [ ] **Step 1: Write the failing test**

Append before the final `print`:

```lua
local statusline = require("config.minimal.statusline")
assert(vim.o.statusline:find("__yf_minimal_statusline", 1, true), "statusline wired")
local line = statusline.render()
assert(type(line) == "string" and #line > 0, "render returns text")
assert(line:find("[No Name]", 1, true), "unnamed buffer label")
local columns = statusline.render()
assert(columns:find("%d+:%d+") ~= nil, "line:column position")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: FAIL because `vim.o.statusline` does not contain the global function.

- [ ] **Step 3: Implement `lua/config/minimal/statusline.lua`**

`setup()` defines `_G.__yf_minimal_statusline` and assigns:

```lua
vim.o.statusline = "%!v:lua.__yf_minimal_statusline()"
```

`render()` returns one line built from:

- mode from `vim.api.nvim_get_mode().mode` mapped to `NORMAL`, `INSERT`,
  `VISUAL`, `V-LINE`, `V-BLOCK`, `COMMAND`, `TERM`, `REPLACE`, wrapped in
  `%#StatusLineMode# mode %#StatusLine#`;
- `vim.fn.expand("%:t")` or `[No Name]`;
- `[+]` when `vim.bo.modified`, `[ro]` when `vim.bo.readonly`;
- diagnostics from `vim.diagnostic.get(0)` counted by severity into
  `%#DiagnosticError#E<n>` / `%#DiagnosticWarn#W<n>` /
  `%#DiagnosticInfo#I<n>` / `%#DiagnosticHint#H<n>` (omit zero counts);
- LSP client count via `pcall(vim.lsp.get_clients, { bufnr = 0 })`, falling
  back to `pcall(vim.lsp.buf_get_clients, 0)`, rendered as `lsp:<n>` only
  when non-zero;
- `filetype`, then `%=` and `line("."):col(".")`.

Use only `vim.diagnostic.get` and `nvim_get_mode`, both present in 0.10.

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: `minimal tests OK`.

- [ ] **Step 5: Commit**

```bash
git add lua/config/minimal/statusline.lua tests/minimal/run.lua
git commit -m "feat(nvim): add built-in statusline to minimal config"
```

---

### Task 4: Built-in pickers

**Files:**
- Modify: `lua/config/minimal/pickers.lua` (replace stub)
- Test: `tests/minimal/run.lua`

**Interfaces:**
- Consumes: `vim.opt.grepprg` set in `config.minimal.setup()`.
- Produces: `require("config.minimal.pickers").setup() -> nil`;
  `.list_files() -> string[]` (sorted, max 5000, no `.git` paths);
  `.grep_command(pattern: string) -> string` returning the Ex command
  `"grep! " .. vim.fn.shellescape(pattern)`.

- [ ] **Step 1: Write the failing test**

Append before the final `print`:

```lua
local pickers = require("config.minimal.pickers")
local dir = vim.fn.getcwd() .. "/.tmp/minimal-pickers"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/.git", "p")
vim.fn.writefile({ "x" }, dir .. "/a.lua")
vim.fn.writefile({ "x" }, dir .. "/.git/config")
vim.fn.chdir(dir)
local files = pickers.list_files()
assert(vim.tbl_contains(files, "a.lua"), "lists regular files")
for _, file in ipairs(files) do
  assert(not file:find("/.git/", 1, true) and not file:match("^%.git/"), ".git must be excluded")
end
vim.fn.mkdir(dir .. "/empty", "p")
vim.fn.chdir(dir .. "/empty")
assert(#pickers.list_files() == 0, "empty directory returns no files")
vim.fn.chdir(vim.fn.getcwd():gsub("/%.tmp/minimal%-pickers/empty$", ""))
assert(pickers.grep_command("a b'c") == "grep! " .. vim.fn.shellescape("a b'c"), "grep is shell-escaped")
assert(vim.fn.maparg("<leader><space>", "n") ~= "", "find-files map")
assert(vim.fn.maparg("<leader>/", "n") ~= "", "grep map")
assert(vim.fn.maparg("<leader>e", "n") ~= "", "explorer map")
```

Note for the implementer: restore the working directory with
`vim.fn.chdir(vim.fn.getcwd():sub(1, -#("/empty") - 1))`-style logic or by
saving `local repo = vim.fn.getcwd()` before the first `chdir`; adjust the
test above accordingly rather than matching on a path pattern.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: FAIL because `pickers.list_files` is nil.

- [ ] **Step 3: Implement `lua/config/minimal/pickers.lua`**

- `M.list_files()`: `vim.fn.glob("**/*", false, true)`, drop directories via
  `vim.fn.isdirectory`, drop any path matching `(^|/)%.git/`, deduplicate,
  sort, cap at 5000.
- `find_files()`: `vim.ui.select(M.list_files(), { prompt = "Find file", kind = "file" }, ...)`
  and `vim.cmd.edit(vim.fn.fnameescape(choice))` on selection.
- `M.grep_command(pattern)`: `"grep! " .. vim.fn.shellescape(pattern)`.
- `grep()`: `vim.ui.input({ prompt = "Grep: " })`, no-op on empty input, else
  `vim.cmd(M.grep_command(input))` then `vim.cmd("copen")`.
- `setup()` maps `<leader><space>` to `find_files`, `<leader>/` to `grep`,
  `<leader>e` to `<cmd>Explore<cr>`, and `<leader>gg` to
  `:terminal lazygit` only when `vim.fn.executable("lazygit") == 1`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: `minimal tests OK`.

- [ ] **Step 5: Clean up the test directory**

The test ends with `vim.fn.delete(dir, "rf")` plus the original `chdir` back
to the repo root. Confirm `git status --short` shows no `.tmp/minimal-pickers`.

- [ ] **Step 6: Commit**

```bash
git add lua/config/minimal/pickers.lua tests/minimal/run.lua
git commit -m "feat(nvim): add built-in file find and grep pickers"
```

---

### Task 5: Keymaps

**Files:**
- Modify: `lua/config/minimal/keymaps.lua` (replace stub)
- Test: `tests/minimal/run.lua`

**Interfaces:**
- Consumes: `config.ComplexKeymaps.build` (`M.run(target)`), present in the
  repo and plugin-free; leader is already `" "`.
- Produces: `require("config.minimal.keymaps").setup() -> nil`;
  `.toggle_comment_and_next()`, `.close_others()`, `.code_action()`.

- [ ] **Step 1: Write the failing test**

Append before the final `print`:

```lua
local keymaps = require("config.minimal.keymaps")
for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>", "<S-h>", "<S-l>", "[b", "]b", "<C-s>", "<C-a>", "<F2>", "<F11>", "<F12>", "<leader>cb", "<leader>cc", "<leader>fw", "[d", "]d", "[q", "]q" }) do
  assert(vim.fn.maparg(lhs, "n") ~= "", "missing mapping " .. lhs)
end
assert(vim.fn.maparg("<leader>bb", "n") ~= "", "alternate buffer map")

vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
vim.bo.commentstring = "-- %s"
vim.bo.filetype = "lua"
keymaps.toggle_comment_and_next()
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "-- foo", "F2 comments")
assert(pcall(vim.cmd, "normal [d"), "diagnostic jump must not error")
assert(pcall(keymaps.code_action), "F11 must not error without LSP")
vim.cmd("enew")
vim.cmd("enew")
keymaps.close_others()
assert(#vim.fn.getbufinfo({ buflisted = 1 }) == 1, "F12 keeps one buffer")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: FAIL with `missing mapping <C-h>`.

- [ ] **Step 3: Implement `lua/config/minimal/keymaps.lua`**

Port these mappings (all plugin-free):

- `j`/`k` and arrows: `v:count == 0 ? 'gj' : 'j'` style expr maps for
  `n`/`x`; `<C-h/j/k/l>` window navigation; `<C-arrow>` resize.
- `<A-j>`/`<A-k>` line move for `n`/`i`/`v` (LazyVim implementations).
- `<S-h>`/`<S-l>`, `[b`/`]b`: previous/next buffer; `<leader>bb` and
  `` <leader>` ``: `:e #`; `<leader>bd`: `bdelete`; `<leader>bo`:
  `M.close_others()`.
- `<C-s>` save for `i`/`x`/`n`/`s`; `<C-a>` select-all for `n`/`i`/`v`;
  `<esc>` clear search for `i`/`n`/`s`; better `n`/`N` expr maps;
  `<`/`>` keep selection; `,`/`.`/`;` undo breakpoints.
- `<leader>ur` redraw/clear search; `<leader>fn` new file;
  `<leader>K` keywordprg; `<leader>fw` notify full path.
- `[q`/`]q`, `<leader>xq` quickfix; `[d`/`]d`, `[e`/`]e`, `[w`/`]w`,
  `<leader>cd` diagnostics using `vim.diagnostic.goto_next/goto_prev`
  (0.10 signature) with a `vim.diagnostic.jump` branch only when that
  function exists.
- `<F11>`: `M.code_action()` (open code action when `vim.lsp.get_clients`
  reports a client, else notify "No LSP client attached").
- `<F12>`: `M.close_others()` with the logic from
  `lua/config/ComplexKeymaps/close-others.lua` (skip terminal/explorer
  buffers, re-list the current one, notify).
- `<F2>`: `M.toggle_comment_and_next()` for `n`/`v`/`i`, using built-in
  `normal! gcc` (normal/insert) and `normal! gc` (visual), moving one line
  down and restoring insert mode.
- `<leader>cb`/`<leader>cc`: `require("config.ComplexKeymaps.build").run()`
  and `.run("clean")`.
- `<leader>cf`: `vim.lsp.buf.format({ async = true })` when a client is
  attached, else notify "No LSP formatter".

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim --headless -u NONE -l tests/minimal/run.lua`
Expected: `minimal tests OK`.

- [ ] **Step 5: Commit**

```bash
git add lua/config/minimal/keymaps.lua tests/minimal/run.lua
git commit -m "feat(nvim): port plugin-free keymaps to minimal config"
```

---

### Task 6: Pi integration, setup guard, docs, and deployment

**Files:**
- Modify: `plugin/disasm.lua:1`
- Modify: `provision/migrations/core.py` (imports and `bootstrap_nvim_plugins_check`)
- Create: `tests/setup/test_core.py`
- Modify: `README.md` (TOC, new section, migration table row)
- Deploy to: `192.168.1.109`

**Interfaces:**
- Consumes: all earlier modules.
- Produces: `provision.migrations.core.nvim_plugins_bootstrapped(home: Path, rpi_marker: Path = Path("/etc/rpi-issue")) -> bool`.

- [ ] **Step 1: Write the failing Python test**

Create `tests/setup/test_core.py`:

```python
import tempfile
import unittest
from pathlib import Path

from provision.migrations.core import nvim_plugins_bootstrapped


class NvimBootstrapCheckTest(unittest.TestCase):
    def test_rpi_marker_skips_bootstrap(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "rpi-issue"
            marker.write_text("", encoding="utf-8")
            self.assertTrue(nvim_plugins_bootstrapped(home, marker))

    def test_lazy_dir_means_bootstrapped(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "missing-marker"
            (home / ".local" / "share" / "nvim" / "lazy").mkdir(parents=True)
            self.assertTrue(nvim_plugins_bootstrapped(home, marker))

    def test_nothing_installed(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "missing-marker"
            self.assertFalse(nvim_plugins_bootstrapped(home, marker))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.setup.test_core -v`
Expected: FAIL with `ImportError: cannot import name 'nvim_plugins_bootstrapped'`.

- [ ] **Step 3: Implement the bootstrap helper and guard**

In `provision/migrations/core.py`, add `from pathlib import Path` and a
module-level function:

```python
def nvim_plugins_bootstrapped(home: Path, rpi_marker: Path = Path("/etc/rpi-issue")) -> bool:
    """Raspberry Pi runs the plugin-free config; there is nothing to sync."""
    if rpi_marker.is_file():
        return True
    return (home / ".local" / "share" / "nvim" / "lazy").is_dir()
```

Replace the body of the nested `bootstrap_nvim_plugins_check()` with
`return nvim_plugins_bootstrapped(home)`.

- [ ] **Step 4: Run the Python test to verify it passes**

Run: `python3 -m unittest tests.setup.test_core -v`
Expected: 3 tests pass.

- [ ] **Step 5: Guard the disassembly plugin**

Prepend to `plugin/disasm.lua`:

```lua
-- The minimal (Raspberry Pi) config has no plugins and does not need the
-- disassembly module; plugin/ scripts run even without lazy.nvim.
if vim.g.yf_minimal then
  return
end
```

- [ ] **Step 6: Update README**

Add to the TOC after `Manual steps`:
`  - [Lightweight Neovim on Raspberry Pi](#lightweight-neovim-on-raspberry-pi)`.

After the "Start Neovim" step, add:

```markdown
### Lightweight Neovim on Raspberry Pi

On a Raspberry Pi (detected via `/etc/rpi-issue`) Neovim loads a plugin-free
config from `lua/config/minimal/`: no LazyVim, no lazy.nvim, no plugin scan.
It keeps LazyVim-like options (line numbers, 2-space indent, sign column),
a hand-written Nord-like colorscheme, a built-in status line, the plugin-free
keymaps (window/buffer navigation, `<C-a>`, `<F2>`, `<F11>`, `<F12>`,
`<leader>cb/cc`), and built-in stand-ins for file find (`<leader><space>`),
grep (`<leader>/`), the file explorer (`<leader>e`), and lazygit
(`<leader>gg`, when installed). There is no completion, Treesitter, LSP UI,
or git-sign integration.

Force it on any machine with `YF_NVIM_MINIMAL=1 nvim`, or opt out on a Pi
with `YF_NVIM_MINIMAL=0 nvim`.
```

Update the `bootstrap_nvim_plugins` row in the migration table to:
`Headless nvim plugin/parser/Mason bootstrap (skipped on Raspberry Pi, which runs the plugin-free config)`.

- [ ] **Step 7: Run the local verification suite**

Run each command from the repo root:

```bash
python3 -m unittest discover -s tests/setup
nvim --headless -u NONE -l tests/profile/run.lua
nvim --headless -u NONE -l tests/minimal/run.lua
python3 -m compileall provision
bash -n setup.sh
```

Expected: all pass; profile test prints `profile tests OK`; minimal test prints `minimal tests OK`.

- [ ] **Step 8: Verify the local minimal path end-to-end**

Run:
`YF_NVIM_MINIMAL=1 nvim --headless -c 'lua assert(vim.g.yf_minimal == true)' -c 'lua assert(vim.fn.exists(":Lazy") == 0)' -c 'lua assert(vim.fn.exists(":DisasmOpen") == 0)' -c qa`
Expected: exit code 0, no messages.

- [ ] **Step 9: Commit and push**

```bash
git add plugin/disasm.lua provision/migrations/core.py tests/setup/test_core.py README.md docs/superpowers
git commit -m "feat: run plugin-free Neovim config on Raspberry Pi"
```

Push with the Docker/deploy-key command in README "Committing & pushing",
then run `git fetch origin main` on the host.

- [ ] **Step 10: Deploy and verify on the Pi**

```bash
ssh 192.168.1.109 'cd ~/.config/nvim && git pull --ff-only'
ssh 192.168.1.109 'cd ~/.config/nvim && nvim --headless -c "lua assert(vim.g.yf_minimal == true)" -c "lua assert(vim.fn.exists(\":Lazy\") == 0)" -c qa'
ssh 192.168.1.109 'cd ~/.config/nvim && nvim --headless -u NONE -l tests/minimal/run.lua'
ssh 192.168.1.109 'cd ~/.config/nvim && nvim --headless -c "lua assert(vim.fn.exists(\":DisasmOpen\") == 0)" -c qa'
```

Expected: `git pull` is a fast-forward; all headless commands exit 0; the
minimal test prints `minimal tests OK`.

- [ ] **Step 11: Run the Pi's own setup check (no plugin bootstrap)**

```bash
ssh 192.168.1.109 'cd ~/.config/nvim && python3 -c "from pathlib import Path; from provision.migrations.core import nvim_plugins_bootstrapped as b; print(b(Path.home()))"'
```

Expected: `True` (the lazy dir already exists, and the Pi marker would skip it
even on a fresh machine).

- [ ] **Step 12: Commit any verification fixes**

Only if a previous step required changes:

```bash
git add -A
git commit -m "fix: address Raspberry Pi verification findings"
```

Push the same way as Step 9, then re-run Step 10.

---

## Self-Review Notes

- Spec coverage: detection, options, colors, keymaps, statusline, pickers,
  disassembly guard, setup guard, tests, README, rollout are all in Tasks
  1-6.
- Type consistency: all modules export `setup()`; `pickers.list_files()`
  returns `string[]`; `statusline.render()` returns `string`;
  `core.nvim_plugins_bootstrapped(home, rpi_marker)` matches its test.
- The test suite accumulates assertions in one file; each task runs the whole
  file, which keeps earlier behavior pinned.
