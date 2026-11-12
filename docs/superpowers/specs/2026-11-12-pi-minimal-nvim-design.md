# Raspberry Pi plugin-free Neovim - design

Date: 2026-11-12
Status: draft

## Intent

`192.168.1.109` (Raspberry Pi, Debian trixie, Neovim 0.10.4, 955 MB RAM,
91 MB free) cannot start this config. `init.lua` has an RPi branch, but its
guard is `vim.osname == "Linux"`, and `vim.osname` does not exist in Neovim
(it is `nil` even on 0.12.6). The branch never runs, LazyVim loads, and
LazyVim refuses to start on Neovim < 0.11.2.

The owner does not need plugin functionality on the Pi. They want an editor
that starts instantly and feels as close as possible to the daily LazyVim
setup: similar options (line numbers, relative numbers, sign column, 2-space
indent), a semi-similar colorscheme (the full config uses `nord.nvim`), the
same leader and the same non-plugin shortcuts.

## Goals

- Neovim opens on the Pi with zero plugins and zero startup errors.
- No lazy.nvim bootstrap, no plugin scan of the existing 751 MB
  `~/.local/share/nvim` tree, no network access at startup.
- Familiar feel: LazyVim-like options, hand-written Nord-like highlights,
  built-in status line, and the plugin-free subset of the current keymaps.
- Works on both the Pi's Neovim 0.10.4 and the development machine's 0.12.6.
- The full LazyVim config on all other machines is unchanged.
- Tested and documented.

## Non-goals

- Completion engine, Treesitter, git signs, pickers with fuzzy scoring,
  LSP server installation, or a plugin manager.
- Upgrading Neovim on the Pi.
- Deleting the existing 751 MB plugin directory (possible follow-up, but
  destructive and not required for this change).
- Reproducing plugin-only keymaps (Telescope/Snacks pickers, which-key,
  Trouble, persistence, etc.).

## Anti-goals

- Any change that makes the full config load the minimal one, or vice versa,
  by accident.
- A second config that silently drifts into a half-maintained LazyVim clone.
  Only stable editor primitives are copied; plugin behavior is not imitated.

## Constraints

- Pi: aarch64, 4 cores, ~91 MB free RAM, used over SSH (Pi-hole/Docker host).
- Debian's Neovim is 0.10.4; no newer apt candidate.
- Must not require external binaries. `rg` and `lazygit` are used only when
  already on PATH.
- Repo convention: `lua/config/*` modules, `docs/superpowers/specs/` design
  docs, `tests/*/run.lua` headless tests, README is the source of truth.

## Approaches considered

| Approach | Summary | Why not / why chosen |
|---|---|---|
| A. Zero-plugin built-in config | Pi branch loads `config.minimal`; no lazy.nvim; Nord-like highlights and LazyVim-like options in Lua | **Chosen.** Instant startup, lowest RAM, no second plugin tree. |
| B. Tiny plugin set | lazy.nvim + nord.nvim, Comment.nvim, gitsigns, statusline | Closer colors/git signs, but adds a plugin manager and maintenance path for little benefit; owner said nothing would be missed. |
| C. Upgrade Neovim + existing `minimal` profile | Install 0.11+ arm64 build, keep LazyVim | Still runs LazyVim on a 955 MB machine with ~91 MB free; contradicts "very lightweight". |

## Decisions

### Detection and layout

- `init.lua` loads the minimal config when `/etc/rpi-issue` is readable.
- `YF_NVIM_MINIMAL=1` forces it and `YF_NVIM_MINIMAL=0` disables it, for
  testing on any machine. The broken `vim.osname` condition is removed.
- The branch sets `vim.g.yf_minimal = true`, requires `config.minimal`, and
  returns before `config.lazy`.
- Files: `lua/config/minimal/init.lua` (entry + options), `colors.lua`,
  `keymaps.lua`, `statusline.lua`, `pickers.lua`.
- `plugin/disasm.lua` returns early when `vim.g.yf_minimal` is set, because
  `plugin/` scripts run even without plugins and the disassembly module is
  not needed on the Pi. `after/ftplugin/asm.lua` stays: it is plugin-free and
  only runs for asm buffers.

### Options

Copy the stable LazyVim defaults that define the feel: `mapleader = " "`,
`maplocalleader = "\\"`, number/relativenumber, signcolumn `yes`,
cursorline, 2-space expandtab, shiftround, smartindent, ignorecase/smartcase,
scrolloff 4, splitright/splitbelow, mouse, termguicolors, undofile,
`laststatus = 3`, `showmode = false`, fillchars with spaces instead of the
LazyVim icon glyphs, `shadafile = "NONE"`, and LazyVim's SSH-aware clipboard
rule. Version-sensitive options (`jumpoptions`, `smoothscroll`,
`winminwidth`) are applied through `pcall` so 0.10.4 ignores what it lacks.

### Colors

Apply a base built-in colorscheme, then override ~50 highlight groups with
the Nord palette: Polar Night backgrounds (#2E3440/#3B4252/#434C5E), Snow
Storm foreground (#D8DEE9), Frost accents (#88C0D0/#81A1C1/#8FBCBB), Aurora
for diagnostics (#BF616A/#EBCB8B/#A3BE8C/#B48EAD). Covers syntax, UI,
diagnostics, diff, popup menu, search, and status line groups.

### Keymaps

Only built-in operations, matching the current bindings where they exist:
window navigation (`<C-h/j/k/l>`), window resize (`<C-arrow>`), line move
(`<A-j/k>`), buffers (`<S-h>/<S-l>`, `[b/]b`, `<leader>bb`, `` <leader>` ``,
`<leader>bd`, `<leader>bo`), `<C-s>` save, `<C-a>` select all, Esc clears
search, better `n`/`N`, `<`/`>` keep selection, undo breakpoints, quickfix
(`[q/]q`, `<leader>xq`), diagnostics (`[d/]d`, `[e/]e`, `[w/]w`,
`<leader>cd`), redraw (`<leader>ur`), `<leader>fn`, `<leader>K`,
`<leader>fw`, `<F11>` code action, `<F12>` close other buffers.

Personal bindings kept as-is: `<F2>` toggles the comment and moves down in
normal/visual/insert (built-in `gc`/`gcc`, no Comment.nvim), `<leader>cb`
and `<leader>cc` call the existing plugin-free
`config.ComplexKeymaps.build`.

Built-in stand-ins for plugin-only actions:

| Keys | LazyVim action | Minimal implementation |
|---|---|---|
| `<leader><space>` | find files | `glob("**/*")` + `vim.ui.select` |
| `<leader>/` | live grep | prompt + `:grep` (`rg --vimgrep` if present, else `grep -Rn`) into quickfix |
| `<leader>e` | file explorer | built-in `:Explore` (netrw) |
| `<leader>gg` | lazygit | `:terminal lazygit` when executable |
| `<leader>cf` | format | `vim.lsp.buf.format` when an LSP client exists, else notify |

Plugin-only keys with no honest built-in equivalent are omitted rather than
mapped to something misleading.

### Status line

A small Lua status line with mode, file name/flags, diagnostics counts,
LSP client count, filetype, and line:column; rendered through
`vim.o.statusline` with `laststatus = 3`. Uses only 0.10-compatible APIs
(`vim.diagnostic.get`, not `vim.diagnostic.count`).

### Setup integration

`bootstrap_nvim_plugins.check()` returns true on `/etc/rpi-issue` so a fresh
Pi setup records the migration instead of running the LazyVim headless sync
(which would now load the minimal config). README's migration table row gains
a short note.

## Testing

- New `tests/minimal/run.lua`, run with
  `nvim --headless -u NONE -l tests/minimal/run.lua`:
  - runtime path points at the repo, `require("config.minimal")` succeeds;
  - key options and mapleader are set;
  - Nord `Normal`/`Comment` highlight groups exist with expected colors;
  - representative keymaps resolve (`<leader><space>`, `<F2>`, `<F12>`,
    `<C-h>`), and `:Lazy` is not defined;
  - no paths under `~/.local/share/nvim/lazy` are added to the runtime path.
- Run that test on the development machine (0.12.6) and on the Pi (0.10.4)
  over SSH.
- On the Pi: `nvim --headless` loads the real config without errors;
  `nvim --headless -c 'lua print(#vim.tbl_keys(package.loaded))' -c qa` is
  used only as a smoke check, not a threshold.
- Existing suites stay green: `python3 -m unittest discover -s tests/setup`,
  `nvim --headless -u NONE -l tests/profile/run.lua`,
  `python3 -m compileall provision`, `bash -n setup.sh`.

## Rollout

Commit on `main` and push with the documented Docker/deploy-key method, then
`git -C ~/.config/nvim pull` on the Pi and open `nvim` normally. If anything
is wrong, `YF_NVIM_MINIMAL=0 nvim` proves whether the problem is the minimal
path or the machine.

## Left to the builder

- Exact highlight-group list and palette shades.
- File-find ignore rules and result cap, and the grep prompt wording.
- Splitting the Lua modules if a single file would exceed a comfortable
  reading size.
