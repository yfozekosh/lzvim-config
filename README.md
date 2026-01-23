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
   
   This will install required packages (tmux, git, gcc, neovim, bat), set up tmux plugin manager, symlink configs, and build tmux-mem-cpu-load.

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

## Description

This is a personalized Neovim configuration based on [LazyVim](https://github.com/LazyVim/LazyVim), a modern Neovim starter template. It is tailored for .NET development, with plugins and settings optimized for C# and related workflows. It uses lazy.nvim as the plugin manager and includes custom configurations for an enhanced development experience.

For more information about LazyVim, refer to the [official documentation](https://lazyvim.github.io/).
