# 💤 LazyVim Configuration

## Installation

1. Backup your existing nvim config (if any):

   ```bash
   mv ~/.config/nvim ~/.config/nvim.backup
   ```

2. Clone this configuration:

   ```bash
   git clone git@github.com:yfozekosh/lzvim-config.git ~/.config/nvim
   ```

3. Run the setup script to install dependencies and configure the environment:

   ```bash
   ./setup.sh
   ```
   
   This will install required packages (tmux, git, gcc, neovim, bat), set up tmux plugin manager, symlink configs, and build tmux-mem-cpu-load. It also symlinks `copilot-instructions.md` to `~/.copilot/copilot-instructions.md` (global GitHub Copilot CLI instructions, applied across all repos/sessions).

4. Start Neovim:

   ```bash
   nvim
   ```
   Lazy.nvim will automatically install all plugins on first launch.

## Building nvim-dbee (for WSL users)

If you're using WSL, the dbee backend needs to be built and run on Windows due to Azure authentication requirements. A build script is provided in `plugin-forks/nvim-dbee/build-for-wsl.sh`.

To build the dbee backend:

```bash
cd plugin-forks/nvim-dbee
./build-for-wsl.sh
```

**Note:** This script must be run manually. It builds the Windows executable and places it in `/mnt/c/__Projects/dbee.exe`.

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
