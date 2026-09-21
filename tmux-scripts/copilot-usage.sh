#!/bin/bash
# Displays cached GitHub Copilot AI credit usage (used/total) for the tmux
# status bar, backed by a headless-browser fetch (fetch.js) that uses a saved
# login session (see login.js / README.md in this directory). Refreshing the
# real page takes ~2-3s, so this wrapper caches the result and refreshes in
# the background on a cooldown so tmux always reads instantly.
#
# The widget text is only printed when the Copilot CLI is actually running
# in the active window (any pane), so it doesn't clutter the status bar for
# windows that have nothing to do with Copilot. Args: $1 = active window id
# (tmux's #{window_id}), passed from .tmux.conf's status-right.

# Opt-in: set YF_ENABLE_COPILOT_SYNC=1 (or any non-empty value) to enable.
if [ -z "${YF_ENABLE_COPILOT_SYNC:-}" ]; then
  exit 0
fi

WINDOW_ID="$1"

# Mirrors the copilot detection in window-name.sh: true if any pane in the
# given window has a direct child process whose command line mentions
# "copilot" (the actual foreground program, not the shell hosting it).
window_has_copilot() {
  local wid="$1" pid
  [ -z "$wid" ] && return 1
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if pgrep -P "$pid" -a 2>/dev/null | grep -qi 'copilot'; then
      return 0
    fi
  done < <(tmux list-panes -t "$wid" -F '#{pane_pid}' 2>/dev/null)
  return 1
}

if ! window_has_copilot "$WINDOW_ID"; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/copilot-usage-scraper"
CACHE_FILE="$HOME/.cache/tmux-copilot-usage"
LOCK_FILE="$HOME/.cache/tmux-copilot-usage.lock"
REFRESH_SECONDS=300  # refresh at most every 5 minutes

mkdir -p "$(dirname "$CACHE_FILE")"

refresh_cache() {
  if [ -e "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      return
    fi
  fi
  (
    echo $$ > "$LOCK_FILE"
    result=$(cd "$SCRIPT_DIR" && node fetch.js 2>/dev/null)
    if [ "$result" = "expired" ]; then
      echo "relogin..." > "$CACHE_FILE"
      # Auto-launch the login flow (headed browser via WSLg) so the user just
      # has to enter password/2FA - login.js guards against duplicate windows.
      # Wait for it to finish, then immediately re-fetch so the cache updates
      # right away instead of waiting for the next 5-minute cooldown.
      (cd "$SCRIPT_DIR" && node login.js >/dev/null 2>&1)
      result=$(cd "$SCRIPT_DIR" && node fetch.js 2>/dev/null)
      if [ -n "$result" ] && [ "$result" != "expired" ]; then
        echo "$result" > "$CACHE_FILE"
      fi
    elif [ -n "$result" ]; then
      echo "$result" > "$CACHE_FILE"
    else
      echo "n/a" > "$CACHE_FILE"
    fi
    rm -f "$LOCK_FILE"
  ) &
  disown 2>/dev/null
}

now=$(date +%s)
if [ -f "$CACHE_FILE" ]; then
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  age=$((now - mtime))
  if [ "$age" -ge "$REFRESH_SECONDS" ]; then
    refresh_cache
  fi
  echo "Copilot:[$(cat "$CACHE_FILE")]"
else
  echo "Copilot:[loading...]"
  refresh_cache
fi
