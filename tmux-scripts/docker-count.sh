#!/bin/bash
# Prints the number of running docker containers, or "n/a" if docker is
# not installed or the daemon isn't reachable.
if ! command -v docker &>/dev/null; then
  echo "n/a"
  exit 0
fi

count=$(docker ps -q 2>/dev/null)
status=$?

if [ "$status" -ne 0 ]; then
  echo "n/a"
else
  echo "$count" | grep -c .
fi
