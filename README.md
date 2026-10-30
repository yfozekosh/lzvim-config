# Yurii's LazyVim Configuration

## Contents

- [Installation](#installation)
  - [Quick start (Windows + WSL, fresh machine)](#quick-start-windows--wsl-fresh-machine)
  - [Quick start (Fedora, fresh machine)](#quick-start-fedora-fresh-machine)
  - [Manual steps](#manual-steps)
- [`setup.sh` details](#setupsh-details)
- [Forked/vendored plugins (`plugin-forks/`)](#forkedvendored-plugins-plugin-forks)
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

`setup.sh` is idempotent and safe to re-run any time (e.g. after pulling
new changes) - it only applies migrations that haven't run yet on this
machine.

**How it works:**
- Each migration is a bash function, registered with
  `run_migration "<name>" <function>`.
- Applied migrations are logged to `~/.yf_setup_migrationlog` (one line per
  migration: name, timestamp, `uname -a`). On the next run, any migration
  already present in that log is skipped.
- The target distro (Fedora or Debian/Ubuntu) is auto-detected from
  `/etc/os-release`; most migrations branch on it, and print a warning
  (rather than failing the whole run) for unsupported distros where a
  manual install is needed instead.
- To force a migration to re-run, delete its line from
  `~/.yf_setup_migrationlog` (or the whole file to rerun everything).

**Current migrations (in run order):**

| Migration | What it does |
|---|---|
| `install_packages` | Installs `tmux`, `git`, `gcc`, `neovim`, `bat` (+ build tools on Fedora) |
| `install_cmake` | Installs `cmake` |
| `install_tpm` | Clones the Tmux Plugin Manager (TPM) to `~/.tmux/plugins/tpm`, but only if it isn't already there (checks for the `.git` dir) - previously it blind-cloned with `\|\| true`, which swallowed every failure and could log success without restoring a deleted clone |
| `link_configs` | Symlinks `.tmux.conf`, `.bash_profile_yf`, `.blerc` (ble.sh color/behavior tweaks), `tmux-scripts/` (as `~/.tmux/scripts`), `copilot-instructions.md` (as `~/.copilot/copilot-instructions.md`), and `asm-lsp/.asm-lsp.toml` (as `~/.config/asm-lsp/.asm-lsp.toml`) into place |
| `repair_config_symlinks` | Re-creates any of those symlinks that are missing or point at the wrong path. Runs unconditionally on every `setup.sh` run (it is a no-op when the links are healthy) because `link_configs` is migration-log-guarded and so never re-runs - without this, a deleted `~/.tmux/scripts` silently breaks tmux window auto-naming, since `automatic-rename-format` shells out to `~/.tmux/scripts/window-name.sh` and tmux falls back to empty window names with no error |
| `install_tmux_plugins` | Starts a throwaway tmux server/session if none is running, sets `TMUX_PLUGIN_MANAGER_PATH` explicitly, then runs TPM's non-interactive installer so tmux plugins (`tmux-sensible`, `tmux-which-key`) are installed without needing to press `prefix+I` (works standalone even before tmux.conf has ever been loaded by a live session) |
| `bashrc_source` | Adds `source ~/.bash_profile_yf` to `~/.bashrc` |
| `install_build_essentials` | Installs `gcc-c++`, `cmake`, `vim`, `fastfetch`, `awk`, `bat` |
| `install_tmux_mem_cpu_load` | Builds and installs `tmux-mem-cpu-load` from `app-forks/tmux-mem-cpu-load` |
| `install_dotnet` | Installs .NET runtime dependencies and runs the official `dotnet-install.sh` |
| `install_nodejs` | Installs Node.js + npm (needed by the three migrations below) |
| `install_copilot_cli` | Installs the GitHub Copilot CLI (`npm install -g @github/copilot`) |
| `configure_claude_statusline` | Points Claude Code's `statusLine.command` (in `~/.claude/settings.json`) at `claude-scripts/statusline.sh`, and **repairs** it if it has gone stale. Because that setting stores an absolute path into this repo, it silently breaks if the repo moves, and `~/.claude/settings.json` can be deleted or rewritten by Claude Code itself; the old "only set if unset" logic plus the migration-log guard meant either case stayed broken while `setup.sh` reported success. A genuine customization pointing at a different, existing script is still left alone. Claude Code invokes that script after every response with the session's real cost (its own accounting) and context-window usage; it caches those for the tmux Claude usage widget (`tmux-scripts/claude-usage.sh`, shown only while the active window has the Claude CLI running) and prints a compact summary as Claude Code's own status line. Note: this is real per-session cost, not the monthly-plan quota `/usage` shows - Claude Code's statusLine hook has no rate-limit/quota field to read |
| `install_gh_cli` | Installs the GitHub CLI (`gh`) from the official apt/dnf repo |
| `install_copilot_usage_scraper` | Installs npm deps + Playwright Chromium + OS runtime libs for the tmux Copilot AI-credit usage widget (`tmux-scripts/copilot-usage-scraper/`), shown in the status bar only while the active window has the Copilot CLI running in one of its panes |
| `install_lazygit` | Installs `lazygit` (Fedora via the `atim/lazygit` copr repo; other distros get a warning with manual install instructions) |
| `install_wsl_fonts` | WSL only (runs via `run_migration_if_wsl`, so it stays *unapplied* - and will still run if you move to WSL): installs DejaVu + Liberation font families so KiCad and other GTK apps render with good fonts instead of the default Droid Sans fallback |
| `install_blesh` | Builds and installs [ble.sh](https://github.com/akinomyoga/ble.sh) (Bash Line Editor - fish/zsh-like syntax highlighting, autosuggestions, vim-mode editing for bash) from git source, sources it from `~/.bashrc` |
| `install_win32yank` | WSL only (via `run_migration_if_wsl`, stays unapplied off WSL): installs [`win32yank.exe`](https://github.com/equalsraf/win32yank) to `~/.local/bin` so tmux and nvim can read/write the real Windows clipboard (see "Shared clipboard" section below) |
| `fix_wsl_interop_persistence` | WSL only (via `run_migration_if_wsl`, stays unapplied off WSL): adds a `[boot] command=` line to `/etc/wsl.conf` that re-registers the `WSLInterop` binfmt_misc entry on every boot. Fedora's WSL image ships with `systemd=true`, and systemd's own binfmt handling can wipe out WSL's private `WSLInterop` registration during boot, breaking every `.exe` call (`win32yank.exe`, `clip.exe`, `powershell.exe`, ...) with "cannot execute binary file". Also applies the fix immediately so the current boot doesn't need a restart. |
| `install_riscv_asm_tools` | Installs the RISC-V assembly LSP (`asm-lsp`: prebuilt x86_64 release, or built with cargo on other architectures) and formatter (`rvfmt` from `mattfbacon/riscv-asm-fmt`) into `~/.local/bin`. Installs `cargo` if needed (build dependency only) and builds `rvfmt` from a pinned commit with `patches/riscv-asm-fmt-dollar-symbol.patch`, because upstream rejects `$` in symbols such as `__global_pointer$` |
| `bootstrap_nvim_plugins` | Runs `nvim --headless -c "luafile scripts/headless_bootstrap.lua"` to install every lazy.nvim plugin, treesitter parser, and Mason-managed LSP server/tool up front (using lazy.nvim's `sync({ wait = true })` API so it actually blocks until done), so the first interactive `nvim` launch is instant instead of installing plugins in the background |

See `AGENTS.md` for the convention to follow when adding a new migration
(every migration must be documented here).

## Forked/vendored plugins (`plugin-forks/`)

See [`docs/plugin-forks.md`](docs/plugin-forks.md) for what's vendored in
`plugin-forks/`, what each is based on, and why (including nvim-dbee's WSL
build step).

## C# / Roslyn troubleshooting

C# support is via `seblyng/roslyn.nvim` (`lua/plugins/roslyn.lua`), backed
by a Roslyn language server that's installed and launched through Mason.
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
RISC-V pseudo-instructions/registers/CSRs, and `rvfmt` formatting through
conform.nvim. `.S` files are preprocessed by the C compiler, so `#include` /
`#define` lines show up as comments.

See [`docs/asm.md`](docs/asm.md) for the parser/query details, the RISC-V
hover/completion supplement, the `rvfmt` patch, and how to enable compiler
diagnostics per project.

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
