#!/bin/bash
# Args: $1 = pane_pid (shell pid running in the pane), $2 = pane_current_path, $3 = pane_current_command (fallback name)
shell_pid="$1"
cwd="$2"
fallback="$3"

# Inspect the shell's direct child processes (the actual foreground program)
cmdline=$(pgrep -P "$shell_pid" -a 2>/dev/null | head -1)
# Strip the leading pid that pgrep -a prepends, e.g. "12345 node script.js" -> "node script.js"
args=$(echo "$cmdline" | sed -E 's/^[0-9]+ //')
comm=$(echo "$args" | awk '{print $1}')
comm_base=$(basename "$comm" 2>/dev/null)

if echo "$args" | grep -qi 'copilot'; then
  echo "ai-$(basename "$cwd")"
elif echo "$comm_base" | grep -qiE '^n?vim$'; then
  echo "nvim-$(basename "$cwd")"
elif echo "$comm_base" | grep -qiE '^ssh$'; then
  # Extract the target host: last non-flag arg to ssh (skips -p 2222, -i key, user@host, etc.)
  host=$(echo "$args" | awk '
    { for (i=2; i<=NF; i++) {
        if ($i ~ /^-/) { if ($i ~ /^-[oJlFpi]$/) i++; continue }
        target=$i
      }
      print target
    }')
  host=${host##*@}
  host=${host%%:*}
  if [ -n "$host" ]; then
    echo "ssh-$host"
  else
    echo "$fallback"
  fi
elif [ -n "$args" ]; then
  case "$comm_base" in
    bash|sh|zsh|-bash|-sh|-zsh)
      # A shell running as the foreground child (e.g. a subshell/script) - name like the idle case
      echo "bash-$(basename "$cwd")"
      ;;
    node|nodejs|python|python3|python2|ruby|perl|php|deno|bun)
      # Interpreter: find the first non-flag arg (the script path) and use its basename, no extension
      script=$(echo "$args" | awk '{ for (i=2;i<=NF;i++) { if ($i ~ /^-/) continue; print $i; exit } }')
      if [ -n "$script" ]; then
        name=$(basename "$script")
        name="${name%.*}"
        echo "$name"
      else
        echo "$comm_base"
      fi
      ;;
    dotnet)
      # dotnet run / dotnet path/to/App.dll -> use the dll/project basename, no extension
      target=$(echo "$args" | awk '{ for (i=2;i<=NF;i++) { if ($i ~ /^-/) continue; print $i; exit } }')
      if [ -n "$target" ] && [ "$target" != "run" ]; then
        name=$(basename "$target")
        name="${name%.*}"
        echo "$name"
      else
        echo "$(basename "$cwd")"
      fi
      ;;
    *)
      echo "$comm_base"
      ;;
  esac
else
  echo "bash-$(basename "$cwd")"
fi

