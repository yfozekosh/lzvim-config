# Yurii's LazyVim Configuration

## Contents

- [Installation](#installation)
  - [Quick start (Fedora, fresh machine)](#quick-start-fedora-fresh-machine)
  - [Manual steps](#manual-steps)
- [`setup.sh` details](#setupsh-details)
- [Building nvim-dbee (for WSL users)](#building-nvim-dbee-for-wsl-users)
- [Shared clipboard (Alacritty + tmux + nvim, WSL)](#shared-clipboard-alacritty--tmux--nvim-wsl)
- [Windows setup (Alacritty + Nerd Font)](#windows-setup-alacritty--nerd-font)
- [Committing & pushing](#committing--pushing)
- [Description](#description)

## Installation

### Quick start (Fedora, fresh machine)

One-liner: installs `git` if missing, clones this repo to `~/.config/nvim`,
and runs `setup.sh`:

```bash
sudo dnf install -y git && git clone https://github.com/yfozekosh/lzvim-config.git ~/.config/nvim && cd ~/.config/nvim && bash setup.sh
```

If you'd rather review `setup.sh` before running it (recommended on a
machine you don't fully trust), curl it down first and read it:

```bash
curl -fsSL https://raw.githubusercontent.com/yfozekosh/lzvim-config/main/setup.sh -o /tmp/setup.sh && less /tmp/setup.sh
```

then run the one-liner above once you're happy with it.

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
| `install_tpm` | Clones the Tmux Plugin Manager (TPM) to `~/.tmux/plugins/tpm` |
| `link_configs` | Symlinks `.tmux.conf`, `.bash_profile_yf`, `.blerc` (ble.sh color/behavior tweaks), `tmux-scripts/` (as `~/.tmux/scripts`), and `copilot-instructions.md` (as `~/.copilot/copilot-instructions.md`) into place |
| `install_tmux_plugins` | Starts a throwaway tmux server/session if none is running, sets `TMUX_PLUGIN_MANAGER_PATH` explicitly, then runs TPM's non-interactive installer so tmux plugins (`tmux-sensible`, `tmux-which-key`) are installed without needing to press `prefix+I` (works standalone even before tmux.conf has ever been loaded by a live session) |
| `bashrc_source` | Adds `source ~/.bash_profile_yf` to `~/.bashrc` |
| `install_build_essentials` | Installs `gcc-c++`, `cmake`, `vim`, `fastfetch`, `awk`, `bat` |
| `install_tmux_mem_cpu_load` | Builds and installs `tmux-mem-cpu-load` from `app-forks/tmux-mem-cpu-load` |
| `install_dotnet` | Installs .NET runtime dependencies and runs the official `dotnet-install.sh` |
| `install_nodejs` | Installs Node.js + npm (needed by the two migrations below) |
| `install_copilot_cli` | Installs the GitHub Copilot CLI (`npm install -g @github/copilot`) |
| `install_gh_cli` | Installs the GitHub CLI (`gh`) from the official apt/dnf repo |
| `install_copilot_usage_scraper` | Installs npm deps + Playwright Chromium + OS runtime libs for the tmux Copilot AI-credit usage widget (`tmux-scripts/copilot-usage-scraper/`) |
| `install_lazygit` | Installs `lazygit` (Fedora via the `atim/lazygit` copr repo; other distros get a warning with manual install instructions) |
| `install_blesh` | Builds and installs [ble.sh](https://github.com/akinomyoga/ble.sh) (Bash Line Editor - fish/zsh-like syntax highlighting, autosuggestions, vim-mode editing for bash) from git source, sources it from `~/.bashrc` |
| `install_win32yank` | WSL only: installs [`win32yank.exe`](https://github.com/equalsraf/win32yank) to `~/.local/bin` so tmux and nvim can read/write the real Windows clipboard (see "Shared clipboard" section below) |
| `fix_wsl_interop_persistence` | WSL only: adds a `[boot] command=` line to `/etc/wsl.conf` that re-registers the `WSLInterop` binfmt_misc entry on every boot. Fedora's WSL image ships with `systemd=true`, and systemd's own binfmt handling can wipe out WSL's private `WSLInterop` registration during boot, breaking every `.exe` call (`win32yank.exe`, `clip.exe`, `powershell.exe`, ...) with "cannot execute binary file". Also applies the fix immediately so the current boot doesn't need a restart. |

See `AGENTS.md` for the convention to follow when adding a new migration
(every migration must be documented here).

## Building nvim-dbee (for WSL users)

See [`docs/nvim-dbee.md`](docs/nvim-dbee.md).

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

## Windows setup (Alacritty + Nerd Font)

`windows/alacritty.toml` is the tracked source of truth for the Alacritty
config. `windows/setup.ps1` is run from a **native Windows PowerShell**
(not inside WSL) and:

- Installs Alacritty via `winget` (skips if already installed)
- Installs JetBrainsMono Nerd Font via `winget` (skips if already installed)
- Links `%APPDATA%\alacritty\alacritty.toml` to the repo's copy via
  `\\wsl.localhost\<distro>\...` (real symlink if Developer Mode/admin is
  available, otherwise falls back to a one-time copy - re-run the script
  after editing the repo config to re-sync in that case)

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<distro>\home\<user>\.config\nvim\windows\setup.ps1
```

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
