#!/bin/bash
# Displays the real, authoritative cost Claude Code has tracked for the
# current session (its own accounting, not a local token-count estimate)
# in the tmux status bar. The number comes from claude-scripts/statusline.sh,
# which Claude Code itself invokes after every response via the
# statusLine.command hook configured in ~/.claude/settings.json (see
# setup.sh's configure_claude_statusline migration) - that script writes
# cost.total_cost_usd to $CACHE_FILE below. This script only reads that
# cache; it does no fetching/estimating of its own.
#
# NOTE: this is per-session cost, NOT the monthly-plan quota /usage shows -
# Claude Code's statusLine hook does not expose any rate-limit/quota field,
# so there is currently no local way to surface that number in tmux.
#
# The widget text is only printed when the Claude Code CLI is actually
# running in the active window (any pane), so it doesn't clutter the status
# bar for windows that have nothing to do with Claude. Args: $1 = active
# window id (tmux's #{window_id}), passed from .tmux.conf's status-right.

CACHE_FILE="$HOME/.cache/claude-session-usage.json"
WINDOW_ID="$1"

# Mirrors the copilot detection in window-name.sh/copilot-usage.sh: true if
# any pane in the given window has a direct child process that is the
# Claude Code CLI (the actual foreground program, not the shell hosting it).
window_has_claude() {
  local wid="$1" pid
  [ -z "$wid" ] && return 1
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if pgrep -P "$pid" -a 2>/dev/null | awk '{print $2}' | grep -qiE '^claude$'; then
      return 0
    fi
  done < <(tmux list-panes -t "$wid" -F '#{pane_pid}' 2>/dev/null)
  return 1
}

if ! window_has_claude "$WINDOW_ID"; then
  exit 0
fi

if [ ! -f "$CACHE_FILE" ]; then
  echo "Claude:[warming up...]"
  exit 0
fi

cost=$(grep -oP '"session_cost_usd":\K[0-9.]+' "$CACHE_FILE")

if [ -n "$cost" ]; then
  echo "Claude:[\$$(printf '%.2f' "$cost") session]"
else
  echo "Claude:[n/a]"
fi
