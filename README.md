# Yurii's LazyVim Configuration

## Contents

- [Installation](#installation)
  - [Quick start (Windows + WSL, fresh machine)](#quick-start-windows--wsl-fresh-machine)
  - [Quick start (Fedora, fresh machine)](#quick-start-fedora-fresh-machine)
  - [Manual steps](#manual-steps)
- [`setup.sh` details](#setupsh-details)
- [tmux status bar](#tmux-status-bar)
- [Forked/vendored code (`plugin-forks/` and `app-forks/`)](#forkedvendored-code-plugin-forks-and-app-forks)
- [C# / Roslyn troubleshooting](#c--roslyn-troubleshooting)
- [PlatformIO / clangd (C/C++)](#platformio--clangd-cc)
- [Assembly & linker scripts](#assembly--linker-scripts)
- [Shared clipboard (Alacritty + tmux + nvim, WSL)](#shared-clipboard-alacritty--tmux--nvim-wsl)
- [Windows setup (Alacritty + Nerd Font)](#windows-setup-alacritty--nerd-font)
- [Committing & pushing](#committing--pushing)
- [Description](#description)

## Installation

### Quick start (Windows + WSL, fresh machine)

Assumes WSL is already installed with a Fedora-based distro (`wsl --install
-d FedoraLinux-44` or similar). Run this in a normal **Windows PowerShell**
(not inside WSL) - it downloads and runs
[`windows/quickstart.ps1`](windows/quickstart.ps1), which installs
PowerShell 7, Alacritty and the Nerd Font via `winget`, then detects your
default (non-Docker) WSL distro/user, asks for confirmation, and runs the
Fedora quick start below inside it plus links Alacritty's config:

```powershell
curl -fsSL https://raw.githubusercontent.com/yfozekosh/lzvim-config/main/windows/quickstart.ps1 -o quickstart.ps1; powershell -ExecutionPolicy Bypass -File .\quickstart.ps1
```

### Quick start (Fedora, fresh machine)

One-liner: installs `git` if missing, clones this repo to `~/.config/nvim`,
and runs `setup.sh`:

```bash
sudo dnf install -y git && git clone https://github.com/yfozekosh/lzvim-config.git ~/.config/nvim && cd ~/.config/nvim && bash setup.sh
```

If you already have `~/.config/nvim` populated (e.g. a previous config),
back it up first - see the manual steps below.

### Manual steps

1. Backup your existing nvim config (if any):

   ```bash
   mv ~/.config/nvim ~/.config/nvim.backup
   ```

2. Clone this configuration:

   Via HTTPS (works without SSH keys set up):
   ```bash
   git clone https://github.com/yfozekosh/lzvim-config.git ~/.config/nvim
   ```

   Or via SSH (if you have a key configured):
   ```bash
   git clone git@github.com:yfozekosh/lzvim-config.git ~/.config/nvim
   ```

3. Run the setup script to install dependencies and configure the environment:

   ```bash
   ./setup.sh
   ```
   
   See [`setup.sh` details](#setupsh-details) below for how it works and the
   full list of migrations it runs.

4. Start Neovim:

   ```bash
   nvim
   ```
   Lazy.nvim will automatically install all plugins on first launch.

## `setup.sh` details

`setup.sh` is now a thin bootstrap: it detects the distro, installs `python3`
if missing, and `exec`s `python3 -m provision.main`. The real orchestrator lives
in the `provision/` Python package (stdlib only).

**How it works:**
- Migrations are defined in `provision/migrations/*.py` as `Migration` objects with
  `up`/`down`/`check` callables. Each migration belongs to a feature
  (`core`, `build`, `shell`, `tmux`, `docker`, `git`, `node`, `ai`,
  `frontend`, `dotnet`, `embedded`, `wsl`).
- Features can be selected interactively (curses TUI with a plain numbered
  fallback) or via `--profile`, `--features`, `--all`, `--noninteractive`.
  Profiles: `minimal`, `work`, `frontend`, `embedded`, `dotnet`, `full`.
- `core` installs `gcc` (Treesitter needs a C compiler) but not C++ or CMake;
  select `build` when you need `g++`, `make`, and `cmake`. `embedded` includes
  `build`; `work`, `frontend`, and `dotnet` do not.
- Selection is persisted to `~/.config/yf-nvim/features` and the active
  profile to `~/.config/yf-nvim/profile` (also readable by Neovim via
  `lua/config/profile.lua`).
- Applied migrations are logged to `~/.yf_setup_migrationlog` as
  `apply <name> <timestamp> '<uname>'` / `undo <name> ...`. On re-run, a
  migration that is no longer selected is undone (`run_down` + an `undo`
  log entry); a selected migration that is not applied is applied; one
  already applied is re-run idempotently (its `up` guard repairs a missing
  target without writing another `apply` record).
- `up` migrations check for externally installed targets and skip
  installation when present, still recording the migration.
- Dependencies between features are closed automatically (e.g. `ai` pulls in
  `core` and `node`; `frontend` pulls in `core` and `node`; `docker` pulls in
  `tmux`).
- To force a migration to re-run, delete all of its lines from
  `~/.yf_setup_migrationlog` (or the whole file to rerun everything), or
  append an `apply <name> ...` record.

**Selection and flags:**
- `./setup.sh` with a TTY and no saved selection opens the interactive feature selector.
- `--profile NAME` (`minimal`, `work`, `frontend`, `embedded`, `dotnet`, `full`)
- `--features core,ai,...`
- `--all`
- `--interactive`, `--noninteractive`
- `--purge` (or `SETUP_PURGE=1`) allows down migrations to remove OS packages.
- `NVIM_PROFILE` overrides the saved profile for Neovim; `~/.config/yf-nvim/profile` and `~/.config/yf-nvim/features` hold the persisted selection.

**Current migrations (in run order):**

| Migration | Feature | What it does |
|---|---|---|
| `install_packages` | core | Installs `tmux`, `git`, `gcc`, `neovim`, `bat`, `fastfetch`, `vim`, download tools |
| `link_configs` | core | Symlinks config files and scripts into place |
| `repair_config_symlinks` | core | Re-creates missing/wrong symlinks (runs every run) |
| `install_lazygit` | core | Installs `lazygit` |
| `bootstrap_nvim_plugins` | core | Headless `nvim` plugin/parser/Mason bootstrap |
| `install_cmake` | build | Installs `cmake` |
| `install_build_essentials` | build | Installs `g++`/`build-essential` and `make` |
| `bashrc_source` | shell | Adds `source ~/.bash_profile_yf` to `~/.bashrc` |
| `install_blesh` | shell | Downloads and extracts the prebuilt ble.sh release (no `make`) |
| `install_tpm` | tmux | Clones TPM |
| `install_tmux_plugins` | tmux | Runs TPM installer |
| `install_tmux_mem_cpu_load` | tmux | Compiles it with `build`, otherwise installs the pinned prebuilt; updates an older installed version |
| `install_gh_cli` | git | Installs GitHub CLI |
| `install_nodejs` | node | Installs Node.js + npm (shared by `ai` and `frontend`) |
| `install_copilot_cli` | ai | Installs GitHub Copilot CLI |
| `configure_claude_statusline` | ai | Points Claude Code status line at repo script |
| `install_copilot_usage_scraper` | ai | npm + Playwright deps for usage widget |
| `install_dotnet` | dotnet | Installs .NET SDK; down removes `~/.dotnet` and system dotnet packages |
| `install_riscv_asm_tools` | embedded | Builds `asm-lsp` + `rvfmt` |
| `install_wsl_fonts` | wsl | Installs WSL fonts |
| `install_win32yank` | wsl | Installs `win32yank.exe` |
| `fix_wsl_interop_persistence` | wsl | Fixes WSL interop persistence |

See `AGENTS.md` for the convention to follow when adding a new migration
(every migration must be documented here).

## tmux status bar

`tmux-scripts/memory-status.sh` adds `TMP:used/total` to the right side of the
status bar only when `/tmp` is backed by `tmpfs`/`ramfs`, followed by
`SWP:used/total`.

The right side hides widgets progressively as the client narrows, dropping
the rightmost first:

| Minimum width | Visible on the right |
| --- | --- |
| 200 | path, TMP/SWP, date, Docker, Copilot, Claude, mem-cpu |
| 180 | path, TMP/SWP, date, Docker, Copilot, Claude |
| 160 | path, TMP/SWP, date, Docker, Copilot |
| 120 | path, TMP/SWP, date, Docker |
| 100 | path, TMP/SWP, date |
| 60 | path, TMP/SWP |

`TMP`/`SWP` sits before the clock, so it stays visible while there is room
for the path or date.

The Docker widget is controlled by the `docker` setup feature. When enabled it
shows `Docker:[n]`, or `Docker:[n/a]` when Docker is absent or unreachable.
When disabled it is omitted entirely. Toggle it with `./setup.sh --interactive`
or include/exclude `docker` via `--features`.

## Forked/vendored code (`plugin-forks/` and `app-forks/`)

See [`docs/plugin-forks.md`](docs/plugin-forks.md) for what's vendored in
`plugin-forks/` and `app-forks/`, what each is based on, why it's vendored,
and which local patches it carries.

## C# / Roslyn troubleshooting

C# support is via `seblyng/roslyn.nvim` (`lua/plugins/dotnet/roslyn.lua`), backed
by a Roslyn language server that's installed and launched through Mason
(the `roslyn-language-server` NuGet package from the official registry).
Its project loading depends on `dotnet`/`DOTNET_ROOT` being correct and, for
projects using a private NuGet feed, a `nugetPAT` environment variable
(exported from `~/.nugetPAT` in `.bashrc`). `lua/roslyn_diagnostics.lua`
adds a `:RoslynDoctor` health-check command and turns Roslyn project-load
failures (bad SDK, NuGet 401s, ...) into batched `vim.notify` warnings
instead of them silently sitting in `:LspLog`.

See [`docs/dotnet-roslyn-troubleshooting.md`](docs/dotnet-roslyn-troubleshooting.md)
for the full breakdown of failure modes (including the Roslyn build daemon
being a long-lived shared process that keeps a stale environment across
nvim restarts) and how to diagnose them.

## PlatformIO / clangd (C/C++)

PlatformIO projects (CH32V003, ESP32, ...) are hard for the LSP out of the
box, for two independent reasons:

- clangd needs a `compile_commands.json`. Without one, every `#include` in
  the project is reported as "file not found", and ch32fun's prototypes
  disappear too, because they are guarded by `#if defined(__riscv)`.
- PlatformIO hands the GCC toolchain WCH-specific RISC-V flags that clangd
  cannot parse (`-march=rv32ecxw`, `-mabi=ilp32e`). clangd then aborts the
  preamble with `unknown target CPU 'rv32ecxw'`, which loses *all* include
  paths, even when the database is present.

Both are handled:

1. **Database generation** — `lua/config/autocmds.lua` maintains the
   database. When a C/C++ buffer is opened in a project that has a
   `platformio.ini` (searched upwards from the file) and
   `compile_commands.json` is missing or older than `platformio.ini`, it
   runs `pio run -t compiledb` asynchronously in the project root and
   notifies on start and on finish. Saving `platformio.ini` re-runs it too. A
   failure reports the tail of the build log once per session (so opening
   more files in the same broken project does not respawn the build);
   `:PlatformIOCompiledb` forces a regeneration for the current project.
   Buffers under `.pio/`, unnamed buffers and non-C/C++ filetypes are
   ignored, and a missing `pio` executable gives a single warning. clangd
   watches the database and reloads it itself, so no LSP restart is needed.

2. **Per-project `.clangd`** — kept in the firmware repo (not here), it
   strips the flags clangd cannot parse and fakes the RISC-V predefines:

   ```yaml
   CompileFlags:
     Remove:
       - -march=*
       - -mabi=*
       - -msave-restore
       - -msmall-data-limit=*
     Add:
       - -D__riscv
       - -D__riscv__
   ```

Worth knowing:

- **Starting a new project**: `pio init -b <board>` creates `src/`,
  `include/`, `lib/`, `platformio.ini` and installs the platform/framework;
  then edit the ini, copy a `.clangd` from an existing RISC-V project, and
  add `compile_commands.json` to `.gitignore` (pio's generated `.gitignore`
  only lists `.pio`). Opening a `.c`/`.cpp` file generates the database
  automatically - no manual build step needed.
- Only C/C++ filetypes are handled, because that is what LazyVim's clangd
  extra attaches to. A sketch-only project (`.ino`, filetype `arduino`) gets
  no LSP; add a `.cpp` file or use `:PlatformIOCompiledb`.
- ESP32 (xtensa) projects are only partially supported: upstream clang has
  no xtensa target, so clangd ignores `-mlongcalls` and friends and falls
  back to the host triple, leaving some toolchain headers unresolved
  (`machine/endian.h`). RISC-V-based targets (CH32V, ESP32-C/H) work with
  the `.clangd` above. Don't copy that `.clangd` into an xtensa project - the
  `-D__riscv` defines are wrong there.
- `pio run -t compiledb` writes the database for one environment at a time,
  so with a multi-env `platformio.ini` the last built env wins. The file is a
  build artefact and belongs in `.gitignore`.
- Neovim 0.12 no longer ships `:LspRestart` / `:LspInfo`. Restart the client
  with `:lua vim.lsp.stop_client(vim.lsp.get_clients(), true)` followed by
  `:e`, or `:checkhealth lsp`.

## Assembly & linker scripts

GNU assembler (including RISC-V) and GNU ld linker scripts get tree-sitter
highlighting, an `asm-lsp` language server with a local supplement for
RISC-V pseudo-instructions/registers/CSRs, and formatting through conform.nvim
(`rvfmt` for `asm`, a small `ld-format` helper for `ld` linker scripts that
normalizes indentation from brace nesting). Assembly buffers also complete
project-wide symbols (labels from other `.s`/`.S` files and C
functions/globals) from the linked ELF via `lua/asm_symbols/`, and `K`/`gd`
show and jump to the symbol's definition plus the comment lines above it
via `lua/asm_docs/`. `.S` files
are preprocessed by the C compiler, so `#include` / `#define` lines show up
as comments.

See [`docs/asm.md`](docs/asm.md) for the parser/query details, the RISC-V
hover/completion supplement, the `rvfmt` patch, and how to enable compiler
diagnostics per project. If no compiler errors show up, `:RiscvAsmDoctor`
prints which piece (project `.asm-lsp.toml`, compiler, or compile flags) is
missing.

## Disassembly view

A split that shows the real disassembly of the project's ELF next to the
source, using the ELF's own debug line table. Move the cursor on the C (or
`.s`) side and every instruction attributed to that source line is
highlighted in the asm split; the split scrolls to the first match. Uses
`riscv-none-elf-objdump -d -l -C` (or whatever `vim.g.disasm.objdump`
names) on the actual ELF, so it reflects optimizer output and linker layout.

Commands: `:DisasmOpen [elf]`, `:DisasmClose`, `:DisasmToggle [elf]`,
`:DisasmRefresh`. With no path, the ELF is auto-detected under `out/`,
`build/`, or the project root. Cycle annotations are off by default; `L`
cycles them through both flash latencies, L1-only, and L0-only. When enabled,
the split appends per-basic-block CH32V003 cycle totals (taken/fallthrough for
conditionals), per-line L0/L1 costs (L1 attributes each 2-cycle fetch charge
to the instruction crossing a 4-byte chunk boundary), and why each block starts and ends
(`· block start: target of j 8`, `· end block: conditional bgtz`); L0 totals
that pay the `4k+2` flash penalty are marked `(+1 misaligned)`. Start reasons
are green, end reasons yellow, misalignment red, and annotation text combines
with source-line highlighting. `S` toggles instruction sizes next to addresses
(`15e(4):` / `152(2):`), independently of the cycle annotation mode; a 16-bit
NOP is shown as `c.nop`, while a 32-bit NOP stays `nop`.
A `jal`/`call`/`jalr` call to `ra` also creates a return edge to the following
instruction, so post-call code is annotated; `j`/`tail` do not.
Every instruction is annotated; a block with no statically known entry uses
a cold fallback labeled `(no known entry)`.
Configuration via `vim.g.disasm` (see [`docs/disasm.md`](docs/disasm.md)).

## Shared clipboard (Alacritty + tmux + nvim, WSL)

On WSL, Alacritty runs as a native Windows process, but tmux and nvim run
inside Linux, so a mouse-selection copy or a `y` in nvim only lands in an
internal Linux buffer unless something explicitly bridges it to the real
Windows clipboard. `setup.sh`'s `install_win32yank` migration installs
[`win32yank.exe`](https://github.com/equalsraf/win32yank), which `.tmux.conf`
and `lua/config/options.lua` use to read/write the real Windows clipboard,
and `fix_wsl_interop_persistence` keeps WSL's `.exe` interop working across
reboots. Apps that write the clipboard via an OSC 52 escape sequence (e.g.
the Copilot CLI's click-to-copy) are handled too, including a tmux-
passthrough gotcha that needed a small shell wrapper to work around.

See [`docs/clipboard.md`](docs/clipboard.md) for the full architecture,
the OSC 52/tmux-passthrough gotcha, and the `WSLInterop` persistence fix.

The tmux half of this is **conditional on `win32yank.exe` actually existing**:
`.tmux.conf` wraps its `copy-command`, its copy-mode `y` binding and its
`pane-set-clipboard` hook in an `if-shell 'command -v win32yank.exe'`. Off
WSL the binary is absent, and pointing those at it quietly broke copying to
the *system* clipboard - tmux still filled its own paste buffer, so nothing
looked wrong in the status line, but `set-clipboard on` made tmux swallow
OSC 52 writes (e.g. the Copilot CLI's click-to-copy) into a buffer whose hook
piped them into a missing executable, so the outer terminal never saw them.
On non-WSL the config instead clears `copy-command`, drops the hook, sets
`set-clipboard external` so OSC 52 passes straight through to the terminal,
and rebinds `y` to `copy-selection-and-cancel` (tmux's own buffer). The
`else` branch actively *clears* those settings rather than merely skipping
them, because tmux server options and bindings survive a re-source - a stale
WSL binding would otherwise persist across restarts and reloads.

## Windows setup (Alacritty + Nerd Font)

`windows/alacritty.toml` is the tracked source of truth for the Alacritty
config. `windows/quickstart.ps1` (see the Windows quick start above) runs
this automatically on a fresh machine; `windows/setup.ps1` is the standalone
piece it calls, useful to re-run on its own later (e.g. after editing
`windows/alacritty.toml`, or if Alacritty/the font need reinstalling).
Run it from a **native Windows PowerShell** (not inside WSL):

- Installs Alacritty via `winget` (skips if already installed)
- Installs JetBrainsMono Nerd Font via `winget` (skips if already installed)
- Links `%APPDATA%\alacritty\alacritty.toml` to the repo's copy via
  `\\wsl.localhost\<distro>\...` (real symlink if Developer Mode/admin is
  available, otherwise falls back to a one-time copy - re-run the script
  after editing the repo config to re-sync in that case)
- Creates an "Alacritty (WSL)" shortcut in the Start Menu that launches
  Alacritty straight into the WSL distro (`alacritty.exe -e wsl.exe --cd ~`)

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<distro>\home\<user>\.config\nvim\windows\setup.ps1
```

Alacritty's own default shell (used when you just launch/pin `alacritty.exe`
directly, e.g. from the taskbar) is PowerShell, not WSL - run `wsl` from
inside it to enter the WSL distro, and `exit` drops you back to a live
PowerShell prompt instead of closing the window. For a window that launches
straight into WSL instead, use (or pin) the separate "Alacritty (WSL)"
shortcut created above.

## Committing & pushing

Commits use the local git identity `yfozekosh <yfozekosh@gmail.com>` (matches
the existing repo history; set via `git config user.name`/`user.email` in
this repo, not `--global`).

Pushing is done via a throwaway Docker container using the deploy key stored
at `~/github_deploy_key` (NOT `~/.ssh`) - the host's SSH agent/`~/.ssh` keys
are never used for this repo:

```bash
docker run --rm --entrypoint sh \
  -v /home/yfozekosh/.config/nvim:/repo \
  -v /home/yfozekosh/github_deploy_key:/tmp/deploy_key:ro \
  -w /repo \
  alpine/git \
  -c "git config --global --add safe.directory /repo && \
      cp /tmp/deploy_key /tmp/key && chmod 600 /tmp/key && \
      GIT_SSH_COMMAND='ssh -i /tmp/key -o StrictHostKeyChecking=accept-new' \
      git push git@github.com:yfozekosh/lzvim-config.git HEAD:main"
```

After pushing, run `git fetch origin main` on the host to refresh the local
`origin/main` tracking ref (the container push doesn't update it).

## Description

This is a personalized Neovim configuration based on [LazyVim](https://github.com/LazyVim/LazyVim), a modern Neovim starter template. It is tailored for .NET development, with plugins and settings optimized for C# and related workflows. It uses lazy.nvim as the plugin manager and includes custom configurations for an enhanced development experience.

For more information about LazyVim, refer to the [official documentation](https://lazyvim.github.io/).
