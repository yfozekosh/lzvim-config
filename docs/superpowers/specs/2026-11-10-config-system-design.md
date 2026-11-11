# Sophisticated config system — design

Date: 2026-11-10
Status: implemented

## Intent

The repository mixes several unrelated concerns (base editor, AI tooling, frontend, .NET, embedded/RISC-V, WSL glue) in one flat tree, and `setup.sh` used to be a single growing list of migrations guarded only by an append-only log. We need to choose a subset of the config, add/remove that subset later, and keep Neovim from even loading plugins that belong to a disabled area.

## Goals

- Nvim profiles / feature flags. A profile selects a set of features. Plugins, LazyVim extras, autocmds, keymaps, and options belonging to a disabled feature are not added at all.
- Reversible migrations. Every migration has an up and a down. Re-running setup with a different selection runs down for newly disabled migrations and up for newly enabled ones.
- Interactive setup. Setup can run as a TUI that lets the user toggle features; the selection is persisted and reused.
- Logical areas. Migrations and nvim config are grouped by feature. `setup.sh` is a thin entrypoint over area modules.
- Undo is logged, not erased. The migration log gains `undo <name>` records; a migration is applied only when its last record is `apply`.
- External-install awareness. Up functions detect tools already installed outside the migration and skip the install while still recording the migration as applied.
- No unnecessary build tooling. Profiles that only need runtime packages must not require a C++ compiler, CMake, or `make`.

## Non-goals

- Per-machine secret management (unchanged).
- Uninstalling shared OS packages by default (removal is opt-in via `--purge`/`SETUP_PURGE=1`). Feature-owned tool packages such as the .NET SDK are removed when their feature is unchecked.
- A GUI installer.
- Replacing lazy.nvim or LazyVim.

## Profiles

| Profile | Features |
|---|---|
| minimal | core, shell, tmux, docker, git |
| work | minimal + ai |
| frontend | minimal + frontend |
| embedded | minimal + build + embedded |
| dotnet | minimal + dotnet |
| full (default) | all features applicable to the machine |

`custom` is written when the interactive selector is used. It is authoritative: the persisted `features` file lists every feature explicitly, so a feature added in a newer version stays off until the user opts in. `wsl` is auto-enabled when `/proc/version` contains `microsoft`, regardless of profile.

## Feature registry

| Feature | Migrations | Nvim artifacts | Depends on |
|---|---|---|---|
| core | install_packages, link_configs, repair_config_symlinks, install_lazygit, bootstrap_nvim_plugins | `plugins/core/*` | — |
| build | install_cmake, install_build_essentials | none | core |
| shell | bashrc_source, install_blesh | bash only | — |
| tmux | install_tpm, install_tmux_plugins, install_tmux_mem_cpu_load | none | — |
| docker | none (tmux status widget only) | none | tmux |
| git | install_gh_cli | extra: `lang.git` | — |
| node | install_nodejs | none | core |
| ai | install_copilot_cli, configure_claude_statusline, install_copilot_usage_scraper | `plugins/ai/*`, extra: `ai.copilot-chat` | core, node |
| frontend | none (editor-only) | extras: `lang.typescript`, `lang.angular`, `formatting.prettier` | core, node |
| dotnet | install_dotnet | `plugins/dotnet/*`, roslyn LSP config, dotnet keymaps | core |
| embedded | install_riscv_asm_tools | `plugins/embedded/*`, extra: `lang.clangd`, PlatformIO autocmds, asm keymaps | core |
| wsl (auto) | install_wsl_fonts, install_win32yank, fix_wsl_interop_persistence | WSL clipboard block in `options.lua` | core |

`core` deliberately keeps `gcc` because Neovim's Treesitter parser builds need a working `cc`. It does not install C++, `make`, or CMake. `build` owns those tools. `embedded` is a profile that includes `build`, but the `embedded` feature itself only depends on `core`; embedded tooling uses `gcc` as its linker. `node` is a normal toggleable feature shared by `ai` and `frontend`; a frontend-only profile gets Node without Copilot.

## Migration record

`~/.yf_setup_migrationlog` is a state log:

```
apply install_dotnet 2026-... 'Linux ...'
undo install_dotnet 2026-... 'Linux ...'
```

A migration is applied iff its most recent record is `apply`. Old lines without a leading verb are treated as `apply` for backward compatibility.

## Nvim side

### `lua/config/profile.lua`

- Reads `NVIM_PROFILE` first, then `~/.config/yf-nvim/profile`, then defaults to `full`.
- `NVIM_PROFILE` is a full override: when it names a known profile, the persisted selection file is ignored. This keeps profile smoke tests deterministic.
- Reads feature overrides from `~/.config/yf-nvim/features` (`feature=on/off`). A `profile=custom` line makes that file authoritative; a known profile line resets the base set to that preset.
- Always enables `core`, auto-enables `wsl` on WSL, and applies the dependency closure.
- Exposes `current()`, `features()`, `has(name)`, and `list()`.

### Conditional loading in `lua/config/lazy.lua`

LazyVim is imported first, then feature-gated extras, then the user's own plugin modules. Extras must precede `plugins.*` so own specs can override extra defaults.

```lua
local spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" } }
-- feature-gated extras: lang.git, lang.clangd, ai.copilot-chat,
-- lang.typescript, lang.angular, formatting.prettier
-- then:
table.insert(spec, { import = "plugins.core" })
-- feature-gated plugins.ai / plugins.dotnet / plugins.embedded
```

`lazyvim.json` keeps only general extras. Feature-owned extras are imported conditionally and must not be listed there, or they would leak into disabled profiles.

### Plugin file reorganization

```
lua/plugins/
  core/
    _main.lua
    autosave.lua
    diffview.lua
    fastfetch-dashboard.lua
    last-file-recorder.lua
    make.lua
    noice.lua
    persistence.lua
    smear-cursor.lua
  ai/
    copilot.lua
  dotnet/
    dap-dotnet.lua
    roslyn.lua
  embedded/
    asm.lua
```

### Guarded config

- `options.lua`: roslyn LSP config only when `has("dotnet")`.
- `autocmds.lua`: PlatformIO block only when `has("embedded")`.
- `keymaps.lua`: Copilot Tab accept only when `has("ai")`; dotnet build/format keymaps only when `has("dotnet")`.
- Build keymaps and base options remain core.

## Setup side

### Bootstrap

`setup.sh` is the only entrypoint users run. It:

- detects the distro from `/etc/os-release`;
- installs `python3` with `apt`/`dnf` if it is missing;
- verifies the standard-library imports the orchestrator needs;
- exports `YF_DISTRO` and `PYTHONPATH`;
- `exec`s `python3 -m provision.main "$@"`.

Python is a hard dependency, so unsupported distros get a clear manual-install message and a non-zero exit. No third-party Python packages are used.

### Python package layout

```
setup.sh                  # bash bootstrap: ensure python3, exec provision/main.py
provision/
  main.py                 # argparse, orchestration, reconcile
  common.py               # subprocess, symlinks, package helpers, downloads
  models.py               # Migration, Feature, Profile, MigrationLog, SetupContext
  features.py             # feature DAG, profiles, selection persistence
  tui.py                  # curses selector + plain numbered fallback
  migrations/
    core.py
    build.py
    shell.py
    tmux.py
    git.py
    node.py
    ai.py
    dotnet.py
    embedded.py
    wsl.py
tests/
  setup/                  # unittest coverage for state/features/reconcile
  profile/run.lua         # plain-Lua profile resolution tests
```

### Migration lifecycle

```
desired on  + not applied:           up, log apply
desired on  + applied:               up (idempotent repair), no new log
desired off + applied or check():    down, log undo
desired off + not applied:           skip
always migration (e.g. symlink repair): up every run; log apply only if absent
```

`build_migrations()` loads modules in dependency order: `core`, `build`, `shell`, `tmux`, `git`, `node`, `ai`, `dotnet`, `embedded`, `wsl`. `build` must precede `tmux` because tmux compiles its helper when `build` is selected; `node` must precede `ai` because the Copilot scraper uses npm.

### TUI / CLI

- `./setup.sh` with a TTY and no saved selection opens the interactive selector.
- Explicit `--profile`, `--features`, or `--all` selections never trigger the convenience prompt.
- Flags: `--profile NAME`, `--features LIST`, `--all`, `--interactive`, `--noninteractive`, `--purge`.
- Profiles: `minimal`, `work`, `frontend`, `embedded`, `dotnet`, `full`.
- The curses selector toggles with arrows/j/k, space or 1–9, and finishes with Enter/d. It falls back to a numbered prompt when curses or a TTY is unavailable.
- Dependencies are auto-enabled; a feature cannot be disabled while a selected feature depends on it. WSL features are hidden unless on WSL.
- Selection is persisted to `~/.config/yf-nvim/features` and `~/.config/yf-nvim/profile`.

### Down migrations

- Config-only changes (symlinks, bashrc lines, Claude settings): remove exactly what up added, only if still pointing at this repo.
- Tool installs: remove tool/binary/config when safe. Shared OS packages are removed only with `--purge`; feature-owned tool packages (e.g. the .NET SDK) are removed with the feature.
- WSL system changes: remove the added line, leave the rest of the file intact.
- `bootstrap_nvim_plugins`: no-op.

### External-install checks

Every up begins with an appropriate guard:

- binary tools: `command -v` or an exact path check;
- packages: `rpm -q` / `dpkg -s` or package-manager idempotency;
- git clones: `.git` directory;
- npm globals: `npm ls -g --depth=0 <pkg>`;
- config edits: exact line/key before appending.

If the target is already present externally, up prints `already installed (external) - recording migration` and returns without overwriting it.

### No-compiler paths

- `build` off: `install_tmux_mem_cpu_load` downloads a pinned, checksummed prebuilt Linux binary from this repo's GitHub release into `~/.local/bin`, falling back to `assets/prebuilt/` when the release asset is not available. The committed asset is x86_64 only; other architectures should enable `build`.
- `build` on: tmux compiles the vendored `app-forks/tmux-mem-cpu-load` source out-of-tree with CMake.
- `shell` never needs `make`: `install_blesh` downloads the official `ble-0.3.4.tar.xz` release, verifies its SHA-256, and extracts it into `~/.local/share/blesh`.

## Risks and mitigations

- Two registries (Python + Lua) can drift. Keep the feature set small and this document as the source of truth.
- Down migrations can be destructive. Shared package removal is purge-gated; config removals are guarded by target checks.
- The profile file lives outside the repo, so a fresh clone loses the selection. The default is `full`, reproducing the previous behaviour.
- Prebuilt assets are architecture-specific and must stay checksum-pinned. The committed x86_64 fallback makes a fresh clone work before a release is published.
- LazyVim extras can leak if they remain in `lazyvim.json`. Feature-owned extras are imported only from `lazy.lua`.

## Testing

- `python3 -m unittest discover -s tests/setup`
- `nvim --headless -u NONE -l tests/profile/run.lua`
- `python3 -m compileall provision`
- `bash -n setup.sh`
- Headless profile smoke tests with `NVIM_PROFILE=minimal|frontend|full` and an isolated `YF_NVIM_STATE_DIR`, checking plugin counts and `LazyVim.has_extra(...)`.

## Language choice (added)

### Approaches considered

1. **Stay in bash.** Lowest friction, matches the original code, no new runtime dependency. Weak data structures and testing; dependency tracking and undo logic become hand-rolled associative arrays. Fine for ~30 migrations, but the TUI and DAG handling stay fragile.
2. **Bash bootstrap + Python 3 (stdlib) orchestrator.** A small bash shim installs `python3` if missing, then execs the orchestrator. Python gives real data structures, migration objects with `up`/`down`/`check`, dependency closure, argparse, and a curses TUI from the standard library. Recommended.
3. **Compiled language (Go/Rust).** Best UX and a single binary, but requires a toolchain on the target machine or shipping binaries; overkill and harder for users to patch. Rejected.

### Recommendation

Adopt approach 2. The bash shim remains as `setup.sh`, so the documented one-liner and `./setup.sh` UX are unchanged, but it only bootstraps Python and delegates. Feature DAG, selection, reconcile, and logging live in Python with unit tests under `tests/setup/`.

## Code quality

- Prefer classes/objects over free functions when state or lifecycle is involved: `Migration`, `Feature`, `Profile`, `MigrationLog`, `SetupContext`.
- Keep functions small and single-purpose; no god modules.
- Comments explain *why* and invariants, not *what* the code does. No narration, no commented-out code, no TODO without an owner.
- Type hints on all Python public APIs; dataclasses for value objects.
- No third-party dependencies; stdlib only (`argparse`, `dataclasses`, `pathlib`, `subprocess`, `curses` for the TUI).
- Tests for state parsing, feature resolution, dependency closure, and migration reconciliation live under `tests/setup/`.

### TUI library choice

- Use the standard library `curses` module for the interactive selector when a TTY is available; it ships with Python and needs no install.
- Fall back to a plain numbered prompt loop when `curses` is unavailable or stdout is not a TTY (SSH non-interactive, CI, piped runs).
- No third-party TUI frameworks (textual, rich, blessed, etc.) to keep the zero-dependency bootstrap guarantee.
