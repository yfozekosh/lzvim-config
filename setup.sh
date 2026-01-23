
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
    sudo apt install -y tmux git gcc build-essential neovim bat
  elif [[ "$DISTRO" == "fedora" ]]; then
    sudo dnf install -y tmux git gcc @development-tools neovim bat --skip-unavailable
  else
    echo "Unsupported distro: $DISTRO"
    exit 1
  fi
}
run_migration "install_packages" install_packages

# Migration 2: Install TPM
install_tpm() {
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" || true
}
run_migration "install_tpm" install_tpm

# Migration 3: Symlink configs
link_configs() {
  ln -sf "$PWD/.tmux.conf" "$HOME/.tmux.conf"
  ln -sf "$PWD/.bash_profile_yf" "$HOME/.bash_profile_yf"
}
run_migration "link_configs" link_configs

# Migration 4: Source bash_profile_yf in .bashrc
ensure_bashrc_source() {
  local line='source ~/.bash_profile_yf'
  grep -qxF "$line" "$HOME/.bashrc" || echo "$line" >> "$HOME/.bashrc"
}
run_migration "bashrc_source" ensure_bashrc_source

echo "Setup complete."
