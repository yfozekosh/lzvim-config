#!/bin/bash
# Compact memory-backed /tmp and swap usage for the tmux status bar.
#
# TMP is included only when /tmp is backed by tmpfs/ramfs. SWP is always
# included (even when swap is zero) so the status bar is predictable.
set -u

export LC_ALL=C

strip_unit() {
  # 2.9G -> 2.9G, 6.7Gi -> 6.7G, 0B -> 0
  printf '%s' "$1" | sed -E 's/(iB|B|i)$//'
}

parts=()

fs_type=$(stat -f -c %T /tmp 2>/dev/null || true)
if [ "$fs_type" = "tmpfs" ] || [ "$fs_type" = "ramfs" ]; then
  read -r tmp_used tmp_total < <(
    df -h --output=used,size /tmp 2>/dev/null | awk 'NR == 2 { print $1, $2 }'
  )
  if [ -n "${tmp_used:-}" ] && [ -n "${tmp_total:-}" ]; then
    parts+=("TMP:$(strip_unit "$tmp_used")/$(strip_unit "$tmp_total")")
  fi
fi

read -r swap_used swap_total < <(free -h 2>/dev/null | awk '/^Swap:/ { print $3, $2 }')
if [ -n "${swap_used:-}" ] && [ -n "${swap_total:-}" ]; then
  parts+=("SWP:$(strip_unit "$swap_used")/$(strip_unit "$swap_total")")
fi

(IFS=' '; printf '%s' "${parts[*]:-}")
