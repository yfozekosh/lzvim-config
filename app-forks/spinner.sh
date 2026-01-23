#!/usr/bin/env bash
#
# Run a command with an animated spinner.
#
# Spinners taken from:
# https://github.com/sindresorhus/cli-spinners
#
# Author: Dave Eddy <dave@daveeddy.com>
# Date: January 05, 2026
# License: MIT

SPINNER_PID=
DEBUG=false
THEME=default
CHARS=
CACHE_FILE="${HOME}/.cache/spinner_times.cache"
START_TIME=
CMD_HASH=
CMD_NAME=

usage() {
	local prog=${0##*/}
	cat <<-EOF
	Usage: $prog [options] <cmd>

	Run a command with an animated spinner.

	Options
	  -d               enable debug output
	  -t <theme>       theme to use, default is default
	  --cmd-name <name> use a fixed name for averaging (instead of hashing the full command)
	  -h               print this message and exit
	EOF
}

spinner() {
	local c elapsed avg_display
	while true; do
		for c in "${CHARS[@]}"; do
			elapsed=$(($(date +%s) - START_TIME))
			avg_display=$(get_average_display)
			printf ' %s %ds%s \r' "$c" "$elapsed" "$avg_display"
			sleep .2
		done
	done
}

get_average_display() {
	if [[ -z "$CMD_HASH" ]] || [[ ! -f "$CACHE_FILE" ]]; then
		echo ""
		return
	fi
	local avg
	avg=$(grep "^${CMD_HASH}:" "$CACHE_FILE" 2>/dev/null | cut -d: -f2)
	if [[ -n "$avg" ]]; then
		echo "/${avg}s"
	fi
}

get_average() {
	if [[ -z "$CMD_HASH" ]] || [[ ! -f "$CACHE_FILE" ]]; then
		echo ""
		return
	fi
	grep "^${CMD_HASH}:" "$CACHE_FILE" 2>/dev/null | cut -d: -f2
}

update_average() {
	local elapsed=$1
	mkdir -p "$(dirname "$CACHE_FILE")"
	
	local old_avg old_count new_avg new_count
	if [[ -f "$CACHE_FILE" ]] && grep -q "^${CMD_HASH}:" "$CACHE_FILE" 2>/dev/null; then
		old_avg=$(grep "^${CMD_HASH}:" "$CACHE_FILE" | cut -d: -f2)
		old_count=$(grep "^${CMD_HASH}:" "$CACHE_FILE" | cut -d: -f3)
		old_count=${old_count:-1}
		new_count=$((old_count + 1))
		new_avg=$(( (old_avg * old_count + elapsed) / new_count ))
		sed -i "s/^${CMD_HASH}:.*/${CMD_HASH}:${new_avg}:${new_count}/" "$CACHE_FILE"
	else
		echo "${CMD_HASH}:${elapsed}:1" >> "$CACHE_FILE"
	fi
}

debug() {
	if $DEBUG; then
		echo "[$$] $*" >&2
	fi
}

cleanup() {
	if [[ -n $SPINNER_PID ]]; then
		debug "killing spinner ($SPINNER_PID)"
		kill "$SPINNER_PID"
	fi

	debug 'finished spinner'
}

load-theme() {
	local theme=$1

	case "$theme" in
		default) CHARS=('\' '|' '/' '-');;
		dots) CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏);;
		pong) CHARS=(
			  "▐⠂       ▌"
			  "▐⠈       ▌"
			  "▐ ⠂      ▌"
			  "▐ ⠠      ▌"
			  "▐  ⡀     ▌"
			  "▐  ⠠     ▌"
			  "▐   ⠂    ▌"
			  "▐   ⠈    ▌"
			  "▐    ⠂   ▌"
			  "▐    ⠠   ▌"
			  "▐     ⡀  ▌"
			  "▐     ⠠  ▌"
			  "▐      ⠂ ▌"
			  "▐      ⠈ ▌"
			  "▐       ⠂▌"
			  "▐       ⠠▌"
			  "▐       ⡀▌"
			  "▐      ⠠ ▌"
			  "▐      ⠂ ▌"
			  "▐     ⠈  ▌"
			  "▐     ⠂  ▌"
			  "▐    ⠠   ▌"
			  "▐    ⡀   ▌"
			  "▐   ⠠    ▌"
			  "▐   ⠂    ▌"
			  "▐  ⠈     ▌"
			  "▐  ⠂     ▌"
			  "▐ ⠠      ▌"
			  "▐ ⡀      ▌"
			  "▐⠠       ▌"
			  );;
		*)
			echo "invalid theme: $THEME" >&2;
			usage >&2;
			exit 1
			;;
	esac
}

main() {
	local opt OPTIND OPTARG
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-d) DEBUG=true; shift;;
			-h) usage; return 0;;
			-t) THEME=$2; shift 2;;
			--cmd-name) CMD_NAME=$2; shift 2;;
			--) shift; break;;
			-*) echo "Unknown option: $1" >&2; usage >&2; return 1;;
			*) break;;
		esac
	done

	load-theme "$THEME"

	if (($# == 0)); then
		usage >&2
		return 1
	fi

	# Generate hash from command for caching
	# Use CMD_NAME if provided, otherwise hash the full command
	if [[ -n "$CMD_NAME" ]]; then
		CMD_HASH=$(echo -n "$CMD_NAME" | md5sum | cut -d' ' -f1)
	else
		CMD_HASH=$(echo -n "$*" | md5sum | cut -d' ' -f1)
	fi
	START_TIME=$(date +%s)

	trap cleanup EXIT

	debug 'starting spinner'
	spinner &
	SPINNER_PID=$!

	debug "SPINNER_PID=$SPINNER_PID"

	"$@"
	local exit_code=$?

	# Update average after command completes
	local elapsed=$(($(date +%s) - START_TIME))
	update_average "$elapsed"

	return $exit_code
}

main "$@"
