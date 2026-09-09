
#!/usr/bin/env bash

set -e

MIGRATION_LOG="$HOME/.yf_setup_migrationlog"

touch "$MIGRATION_LOG"

has_migration() {
  grep -q "^$1 " "$MIGRATION_LOG"
}

log_migration() {
  echo "$1 $(date -Iseconds) '$(uname -a)'" >> "$MIGRATION_LOG"
}

# Detect distro
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Cannot detect Linux distribution."
  exit 1
fi

run_migration() {
  local name="$1"
  shift
  if ! has_migration "$name"; then
    echo "Applying migration: $name"
    "$@"
    log_migration "$name"
  else
    echo "Migration $name already applied."
  fi
}

# Migration 1: Install packages
install_packages() {
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    sudo apt update
    sudo apt install -y tmux git gcc build-essential neovim bat wget curl xz-utils gawk
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y tmux git gcc @development-tools neovim bat wget curl xz gawk --skip-unavailable
  else
    echo "Unsupported distro: $DISTRO"
    exit 1
  fi
}
run_migration "install_packages" install_packages

install_cmake() {
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    sudo apt install -y cmake
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y cmake --skip-unavailable
  else
    echo "Unsupported distro: $DISTRO"
    exit 1
  fi
}
run_migration "install_cmake" install_cmake

# Migration 2: Install TPM
install_tpm() {
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" || true
}
run_migration "install_tpm" install_tpm

# Migration 3: Symlink configs
link_configs() {
  ln -sf "$PWD/.tmux.conf" "$HOME/.tmux.conf"
  ln -sf "$PWD/.bash_profile_yf" "$HOME/.bash_profile_yf"
  mkdir -p "$HOME/.tmux"
  ln -sf "$PWD/tmux-scripts" "$HOME/.tmux/scripts"
  mkdir -p "$HOME/.copilot"
  ln -sf "$PWD/copilot-instructions.md" "$HOME/.copilot/copilot-instructions.md"
}
run_migration "link_configs" link_configs

# Migration 3.1: Install tmux plugins (tmux-sensible, tmux-which-key, etc.)
# via TPM's non-interactive installer. TPM resolves its plugin directory via
# the TMUX_PLUGIN_MANAGER_PATH tmux global environment variable, which is
# normally only set the first time tmux.conf's `run '~/.tmux/plugins/tpm/tpm'`
# line executes inside a live session - which never happens on a brand-new
# machine before the first manual tmux launch. Ensure a tmux server is
# running (tmux's default `exit-empty on` kills a server started with no
# session, so use a throwaway detached session rather than bare
# `start-server`) and set the variable explicitly so the installer works
# standalone. If a server is already running (e.g. re-running setup.sh on an
# already-configured machine), leave it untouched.
install_tmux_plugins() {
  local started_temp_session=0
  if ! tmux info &>/dev/null; then
    tmux new-session -d -s __tpm_setup__
    started_temp_session=1
  fi
  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$HOME/.tmux/plugins/"
  "$HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
  if [ "$started_temp_session" -eq 1 ]; then
    tmux kill-session -t __tpm_setup__ 2>/dev/null || true
  fi
}
run_migration "install_tmux_plugins" install_tmux_plugins

# Migration 4: Source bash_profile_yf in .bashrc
ensure_bashrc_source() {
  local line='source ~/.bash_profile_yf'
  grep -qxF "$line" "$HOME/.bashrc" || echo "$line" >> "$HOME/.bashrc"
}
run_migration "bashrc_source" ensure_bashrc_source

# Migration: install ble.sh (Bash Line Editor) - fish/zsh-like syntax
# highlighting, autosuggestions and vim-mode command line editing for bash.
# Built from the latest git source (rather than the "nightly" release
# tarball) because the nightly tarball hit a Bash 5.3 arithmetic-expansion
# incompatibility (bash 5.3 is stricter about `path[d]`-style array
# subscripts) that the git master already has fixed. Installs to
# ~/.local/share/blesh and sources it from .bashrc.
install_blesh() {
  local blesh_dir="$HOME/.local/share/blesh"
  if [ ! -f "$blesh_dir/ble.sh" ]; then
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$tmp_dir/ble.sh"
    make -C "$tmp_dir/ble.sh"
    make -C "$tmp_dir/ble.sh" install PREFIX="$HOME/.local"
    rm -rf "$tmp_dir"
  fi

  local line='source -- ~/.local/share/blesh/ble.sh'
  grep -qxF "$line" "$HOME/.bashrc" || echo "$line" >> "$HOME/.bashrc"
}
run_migration "install_blesh" install_blesh

#Migration 4.1
install_build_essentials() {
  sudo dnf install -y gcc-c++ cmake
  sudo dnf install -y vim fastfetch awk bat
}

run_migration "install_build_essentials" install_build_essentials

# Migration 5: build tmux-mem-cpu-load
install_tmux_mem_cpu_load() {
  local repo_dir="$PWD/app-forks/tmux-mem-cpu-load"
  if [ ! -d "$repo_dir" ]; then
    echo "cannot find tmux-mem-cpu-load directory at $repo_dir"
    exit 1
  fi

  # save current dir
  pushd $repo_dir
  cmake .
  make
  sudo make install
  popd
}
run_migration "install_tmux_mem_cpu_load" install_tmux_mem_cpu_load


install_dotnet() {
    sudo dnf install -y glibc libgcc ca-certificates openssl-libs libstdc++ libicu tzdata krb5-libs zlib
    wget https://dot.net/v1/dotnet-install.sh -O ~/dotnet-install.sh
    chmod +x ~/dotnet-install.sh
    ~/dotnet-install.sh
}
run_migration "install_dotnet" install_dotnet

# Migration: install Node.js + npm (needed for the Copilot CLI and the
# Copilot usage scraper migration below)
install_nodejs() {
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    sudo apt update
    sudo apt install -y nodejs npm
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y nodejs npm
  else
    echo "Unsupported distro: $DISTRO"
    exit 1
  fi
}
run_migration "install_nodejs" install_nodejs

# Migration: install the GitHub Copilot CLI (this tool)
install_copilot_cli() {
  sudo npm install -g @github/copilot
}
run_migration "install_copilot_cli" install_copilot_cli

# Migration: install GitHub CLI (gh)
install_gh_cli() {
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
    out=$(mktemp)
    wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
    cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages/deb stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y 'dnf-command(config-manager)'
    sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf install -y gh --repo gh-cli
  else
    echo "Unsupported distro: $DISTRO"
    exit 1
  fi
}
run_migration "install_gh_cli" install_gh_cli

# Migration: set up the Copilot AI-credit usage scraper (tmux status bar
# widget). Installs npm deps + Playwright Chromium + Linux runtime libs
# Chromium needs. Credentials/session (state.json, password) are never part
# of the repo - they live in ~/.config/copilot-usage/ and are created by
# tmux-scripts/copilot-usage-scraper/login.js on first run.
install_copilot_usage_scraper() {
  local scraper_dir="$PWD/tmux-scripts/copilot-usage-scraper"
  (cd "$scraper_dir" && npm install)
  (cd "$scraper_dir" && npx playwright install chromium)
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    (cd "$scraper_dir" && npx playwright install-deps chromium) || true
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y nss nspr atk cups-libs libdrm libxkbcommon at-spi2-atk \
      libXcomposite libXdamage libXfixes libXrandr mesa-libgbm alsa-lib \
      pango cairo libxshmfence
  else
    echo "Unsupported distro for Playwright deps: $DISTRO (install manually if the browser fails to launch)"
  fi
}
run_migration "install_copilot_usage_scraper" install_copilot_usage_scraper

# Migration: install lazygit (Fedora via copr; other distros unsupported here)
install_lazygit() {
  if [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf copr enable -y atim/lazygit
    sudo dnf install -y lazygit
  else
    echo "WARNING: install_lazygit migration only supports Fedora (copr atim/lazygit)." >&2
    echo "WARNING: install lazygit manually for distro '$DISTRO': https://github.com/jesseduffield/lazygit#installation" >&2
  fi
}
run_migration "install_lazygit" install_lazygit

echo "Setup complete."
bat ~/.yf_setup_migrationlog
