# Yurii's LazyVim Configuration

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

See `AGENTS.md` for the convention to follow when adding a new migration
(every migration must be documented here).

## Building nvim-dbee (for WSL users)

If you're using WSL, the dbee backend needs to be built and run on Windows due to Azure authentication requirements. A build script is provided in `plugin-forks/nvim-dbee/build-for-wsl.sh`.

To build the dbee backend:

```bash
cd plugin-forks/nvim-dbee
./build-for-wsl.sh
```

**Note:** This script must be run manually. It builds the Windows executable and places it in `/mnt/c/__Projects/dbee.exe`.

## Shared clipboard (Alacritty + tmux + nvim, WSL)

On WSL, Alacritty runs as a native Windows process, but tmux and nvim run
inside Linux, so a mouse-selection copy or a `y` in nvim only lands in an
internal Linux buffer (tmux's paste buffer / nvim's default register) unless
something explicitly bridges it to the real Windows clipboard.

`setup.sh`'s `install_win32yank` migration installs
[`win32yank.exe`](https://github.com/equalsraf/win32yank) to `~/.local/bin`
(it runs as a native Windows process via WSL interop, no X server or
`wl-copy` needed). Two things then use it to read/write the real Windows
clipboard:

- `.tmux.conf` sets `copy-command` to `win32yank.exe -i --crlf`, so both
  mouse-drag copies and `prefix + [` copy-mode `y` write straight to the
  Windows clipboard.
- `lua/config/options.lua` sets `vim.g.clipboard` to use `win32yank.exe` for
  the `+`/`*` registers (only on WSL, only if the binary is found), plus
  `clipboard=unnamedplus`, so nvim yank/paste/delete use the Windows
  clipboard by default.

Since Alacritty is already a native Windows app, its own mouse-selection
copy/paste already uses the Windows clipboard directly - no extra config
needed there. After all three pieces are in place, copying in any of the
three apps and pasting in any other (including into Windows applications)
should just work.

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
