#!/bin/bash
# Claude Code statusLine hook - see ~/.claude/settings.json's
# "statusLine": { "type": "command", "command": "..." } (configured by
# setup.sh's configure_claude_statusline migration). Claude Code invokes
# this after every response with a JSON payload on stdin describing the
# current session: cost.total_cost_usd (the real, authoritative cumulative
# $ spent so far in this session - Claude Code's own accounting, not a
# local estimate), context_window.used_percentage, model, and cwd.
#
# NOTE: there is no rate-limit/quota field in this payload (checked against
# a real payload from Claude Code 2.1.278) - so this can only ever surface
# real per-session cost, not the monthly-plan quota /usage shows.
#
# We cache total_cost_usd to $CACHE_FILE, as flat single-line JSON so
# tmux-scripts/claude-usage.sh can read it with plain grep (no need to
# spawn node on every 2s tmux status-bar refresh), and print a compact
# summary back to stdout, which Claude Code renders as its own status line.

CACHE_FILE="$HOME/.cache/claude-session-usage.json"
mkdir -p "$(dirname "$CACHE_FILE")"

INPUT=$(cat)

node -e '
let data;
try { data = JSON.parse(process.argv[1]); } catch (e) { process.exit(0); }

const cost = data.cost || {};
const ctx = data.context_window || {};
const model = data.model || {};
const effort = data.effort || {};
const workspace = data.workspace || {};
const cwd = workspace.current_dir || data.cwd || workspace.project_dir || "";

const fs = require("fs");
try {
  fs.writeFileSync(process.argv[2], JSON.stringify({
    session_cost_usd: cost.total_cost_usd,
    context_used_pct: ctx.used_percentage,
    updated_at: Math.floor(Date.now() / 1000),
  }) + "\n");
} catch (e) {}

const RESET = "\x1b[0m", RED = "\x1b[31m", ORANGE = "\x1b[38;5;208m", GREEN = "\x1b[32m", DIM = "\x1b[2m", YELLOW = "\x1b[33m", BRIGHT_GREEN = "\x1b[92m";

const parts = [];
if (typeof cost.total_cost_usd === "number") {
  parts.push(`${DIM}session:${RESET} $${cost.total_cost_usd.toFixed(2)}`);
}
if (typeof ctx.used_percentage === "number") {
  const pct = ctx.used_percentage;
  const c = pct > 80 ? RED : pct >= 70 ? ORANGE : GREEN;
  parts.push(`${DIM}ctx:${RESET} ${c}${pct.toFixed(0)}%${RESET}`);
}
let line = parts.join(`  ${DIM}|${RESET}  `);

const modelName = model.display_name || model.id;
const details = [];
if (modelName) details.push(`${YELLOW}${modelName}${effort.level ? " " + effort.level : ""}${RESET}`);
if (cwd) {
  const home = process.env.HOME || "";
  const short = home && cwd.startsWith(home) ? "~" + cwd.slice(home.length) : cwd;
  details.push(`${BRIGHT_GREEN}${short}${RESET}`);
}
if (details.length) line += (line ? "\n" : "") + details.join(` ${DIM}·${RESET} `);

process.stdout.write(line);
' "$INPUT" "$CACHE_FILE"
