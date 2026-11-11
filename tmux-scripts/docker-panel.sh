#!/bin/bash
# Prints the Docker status widget when the "docker" setup feature is enabled.
# When the feature is off, prints nothing. When it is on but Docker is absent
# or unreachable, docker-count.sh prints "n/a".
set -u

state_dir="${YF_NVIM_STATE_DIR:-$HOME/.config/yf-nvim}"
features="$state_dir/features"
profile=""
docker_setting=""

if [ -f "$features" ]; then
  while IFS='=' read -r key value; do
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    case "$key" in
      profile) profile="$value" ;;
      docker) docker_setting="$value" ;;
    esac
  done < "$features"
fi

# Preserve the old visible-by-default behaviour when no selection exists yet.
# A custom selection is authoritative: features added later stay off until the
# user explicitly enables them (matching provision/features.py).
enabled=1
if [ -z "$docker_setting" ] && [ "$profile" = "custom" ]; then
  enabled=0
fi
if [ -n "$docker_setting" ]; then
  case "${docker_setting,,}" in
    on|true|1|yes) enabled=1 ;;
    off|false|0|no) enabled=0 ;;
  esac
fi

[ "$enabled" -eq 1 ] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
count="$("$script_dir/docker-count.sh" 2>/dev/null || printf 'n/a')"
printf ' Docker:[%s]' "$count"
