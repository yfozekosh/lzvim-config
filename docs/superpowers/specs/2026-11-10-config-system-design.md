# Sophisticated config system — design

Date: 2026-11-10
Status: proposed

## Intent

The repository mixes several unrelated concerns (base editor, AI tooling, .NET, embedded/RISC-V, WSL glue) in one flat tree, and `setup.sh` is a single growing list of migrations guarded only by an append-only log. We need to choose a subset of the config, add/remove that subset later, and keep Neovim from even loading plugins that belong to a disabled area.

## Goals

- Nvim profiles / feature flags. A profile selects a set of features. Plugins (and LazyVim extras, autocmds, keymaps, options) belonging to a disabled feature are not added to the lazy.nvim spec at all.
- Reversible migrations. Every migration has an up and a down. Re-running setup.sh with a different selection runs down for newly disabled migrations and up for newly enabled ones.
- Interactive setup. setup.sh can run as a TUI that lets the user toggle features; selection persisted and reused.
- Logical areas. Migrations and nvim config grouped by feature (core, shell, tmux, ai, dotnet, embedded, wsl). setup.sh becomes a thin entrypoint over area modules.
- Undo is logged, not erased. Migration log gains `undo <name>` records; a migration is applied only when its last record is apply.
- External-install awareness. up functions detect tools already installed outside the migration and skip the install while still recording the migration as applied.

## Non-goals

- Per-machine secret management (unchanged).
- Uninstalling OS packages by default (removal opt-in via SETUP_PURGE=1).
- A GUI installer.
- Replacing lazy.nvim or LazyVim.

## Core concepts

### Feature

A feature is a named, toggleable area. Each owns a set of migrations, a set of nvim artifacts, and dependencies.

### Profile

Named preset of features.

| Profile | Features |
|---|---|
| minimal | core, shell, tmux, git |
| work | minimal + ai |
| embedded | minimal + embedded |
| dotnet | minimal + dotnet |
| full (default) | all features applicable to the machine |

wsl is auto-enabled when /proc/version contains microsoft, regardless of profile.

### Migration record

~/.yf_setup_migrationlog becomes a state log:

```
apply install_dotnet 2026-... 'Linux ...'
undo install_dotnet 2026-... 'Linux ...'
```

A migration is applied iff its most recent record is apply. Old lines without a leading verb are treated as apply for backward compatibility.

## Feature registry

| Feature | Migrations | Nvim artifacts |
|---|---|---|
| core | install_packages, install_cmake, link_configs, repair_config_symlinks, install_build_essentials, install_lazygit, bootstrap_nvim_plugins | plugins/core/*, base extras |
| shell | bashrc_source, install_blesh | bash only |
| tmux | install_tpm, install_tmux_plugins, install_tmux_mem_cpu_load | none |
| git | install_gh_cli | extras: lang.git |
| ai | install_nodejs, install_copilot_cli, configure_claude_statusline, install_copilot_usage_scraper | plugins/ai/*, extras: ai.copilot-chat |
| dotnet | install_dotnet | plugins/dotnet/*, roslyn lsp config, dotnet keymaps |
| embedded | install_riscv_asm_tools | plugins/embedded/*, extras: lang.clangd, platformio autocmds, asm keymaps |
| wsl (auto) | install_wsl_fonts, install_win32yank, fix_wsl_interop_persistence | WSL clipboard block in options.lua |

Dependencies: ai -> nodejs (internal), embedded -> core, wsl -> core. nodejs is not user-visible; pulled in by ai.

## Nvim side

### lua/config/profile.lua

Reads NVIM_PROFILE env, then ~/.config/yf-nvim/profile, default full. Reads feature overrides from ~/.config/yf-nvim/features. Exposes current() and has(name).

### Conditional loading in lua/config/lazy.lua

Replace auto-import `{ import = "plugins" }` with explicit imports:

```lua
local P = require("config.profile")
local spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  { import = "plugins.core" },
}
if P.has("ai")       then table.insert(spec, { import = "plugins.ai" }) end
if P.has("dotnet")   then table.insert(spec, { import = "plugins.dotnet" }) end
if P.has("embedded") then table.insert(spec, { import = "plugins.embedded" }) end
if P.has("embedded") then table.insert(spec, { import = "lazyvim.plugins.extras.lang.clangd" }) end
if P.has("ai")       then table.insert(spec, { import = "lazyvim.plugins.extras.ai.copilot-chat" }) end
```

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

### Guarded requires

- options.lua: roslyn lsp config only when has("dotnet").
- autocmds.lua: PlatformIO block only when has("embedded").
- keymaps.lua: dotnet/build requires only when relevant feature on.

## Setup side

### File layout

```
setup.sh
setup/lib/common.sh
setup/lib/features.sh
setup/lib/migrations.sh
setup/lib/tui.sh
setup/migrations/core.sh
setup/migrations/shell.sh
setup/migrations/tmux.sh
setup/migrations/git.sh
setup/migrations/ai.sh
setup/migrations/dotnet.sh
setup/migrations/embedded.sh
setup/migrations/wsl.sh
```

### Migration lifecycle

```
register_migration <name> <feature> <up_fn> <down_fn>
```

Reconcile:

- desired on + not applied: up, log_apply
- desired off + applied: down, log_undo
- desired on + applied: up (idempotent external check), no log
- desired off + not applied: nothing

### TUI / CLI

- ./setup.sh with TTY and no selection file -> interactive.
- --profile NAME
- --features LIST
- --all
- --noninteractive
- --purge
- --interactive

Interactive selector: numbered list with [x]/[ ], toggle by number, d done. Dependencies auto-enabled; cannot disable a feature while a dependent is on. WSL features shown only on WSL and default on.

Selection persisted to ~/.config/yf-nvim/features and profile name to ~/.config/yf-nvim/profile.

### Down migrations

- Config-only (symlinks, bashrc lines, claude settings): remove exactly what up added, only if still pointing at this repo.
- Tool installs: remove tool/binary/config when safe; remove OS packages only with --purge.
- WSL system changes: remove added line, leave file otherwise intact.
- bootstrap_nvim_plugins: no-op.

### External-install checks

Every up begins with an appropriate guard:

- binary tools: command -v or test -x ~/.local/bin/<tool>
- packages: rpm -q / dpkg -s (or rely on package manager idempotency but print)
- git clones: test .git
- npm globals: npm ls -g --depth=0 <pkg>
- config edits: grep exact line/key before appending

If already present externally, up prints "already installed (external) - recording migration" and returns 0.

## Risks and mitigations

- Two registries (bash + Lua) can drift. Keep set small; doc is source of truth.
- Down migrations destructive. purge opt-in; config removals guarded.
- Profile file outside repo means fresh clone loses selection. Default full reproduces today's behaviour.
- LazyVim extras via json vs Lua. Prefer explicit Lua imports for profile-gated extras.

## Testing

- bash -n setup.sh setup/lib/*.sh setup/migrations/*.sh
- Plain-Lua test tests/profile/run.lua for config.profile.
- Manual smoke: ./setup.sh --features core --noninteractive; toggle ai on; verify undo/apply log.
- Manual nvim: NVIM_PROFILE=minimal nvim; check :Lazy.

## Open questions

- Whether nodejs should be user-visible (leaning internal to ai).
- Auto-run interactive whenever selection file missing (leaning yes).
- Whether down migrations remove OS packages even with --purge (leaning yes, but print list and confirm).

## Language choice (added)

### Approaches considered

1. **Stay in bash.** Lowest friction, matches current code, no new runtime
   dependency. Weak data structures and testing; dependency tracking and
   undo logic become hand-rolled associative arrays. Fine for ~30
   migrations, but the TUI and DAG handling stay fragile.
2. **Bash bootstrap + Python 3 (stdlib) orchestrator.** A ~20-line bash
   shim installs `python3` if missing, then execs `setup.py`. Python gives
   real data structures, a migration base class with `up`/`down`/`check`,
   topological dependency resolution, argparse CLI, and a curses/textual-
   free TUI (numbered prompts, or `curses` from stdlib for a richer one).
   Migration bodies can initially be shell strings run via `subprocess`,
   then be ported to Python incrementally. Recommended.
3. **Compiled language (Go/Rust).** Best UX and single binary, but requires
   a toolchain on the target machine or shipping binaries; overkill and
   harder for users to patch. Rejected.

### Recommendation

Adopt approach 2. The migration registry becomes a list of Python objects:

```python
@dataclass
class Migration:
    name: str
    feature: str
    depends: list[str]
    up: Callable[[], None]
    down: Callable[[], None]
    check: Callable[[], bool]   # external-install detection
```

The bash shim remains as `setup.sh` (so the documented one-liner and
`./setup.sh` UX is unchanged), but it only bootstraps Python and delegates.
Feature DAG, selection, reconcile, and logging live in Python with unit
tests under `tests/setup/`.

### Updated file layout

```
setup.sh                  # bash bootstrap: ensure python3, exec setup/main.py
setup/
  main.py                 # argparse, orchestration, reconcile
  features.py             # feature DAG, profiles, selection persistence
  migrations.py           # Migration dataclass + registry
  tui.py                  # interactive selector
  migrations/
    core.py
    shell.py
    ...
tests/setup/
  test_migration_state.py
  test_features.py
```

### Bootstrap guarantees (added)

The bash shim (`setup.sh`) is the only entrypoint users run, so it must work
on a machine with no Python:

- Detect `python3` on PATH; if present, exec the orchestrator.
- Otherwise install it using the detected distro's package manager
  (`dnf install -y python3` / `apt install -y python3`), reusing the same
  distro detection as today.
- For unsupported distros, print a clear manual-install instruction and
  `exit 1` (Python is a hard dependency of the orchestrator, unlike
  optional tools), matching the existing convention for truly required base
  dependencies.
- Verify the installed interpreter can import only the standard library
  (no third-party packages are required anywhere in the stack).
- Pass through all CLI args and the detected distro via environment so the
  Python side does not re-detect inconsistently.
