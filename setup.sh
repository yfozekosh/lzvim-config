#!/usr/bin/env bash

set -e

# Bootstrap: ensure Python 3 is available, then delegate to the orchestrator.
SOURCE="${BASH_SOURCE[0]:-$0}"
REPO_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="${ID:-unknown}"
else
  echo "Cannot detect Linux distribution."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 not found; installing..."
  case "$DISTRO" in
    debian|ubuntu)
      sudo apt update
      sudo apt install -y python3
      ;;
    fedora)
      sudo dnf install -y python3
      ;;
    *)
      echo "Unsupported distro for automatic python3 install: $DISTRO"
      echo "Please install python3 manually, then re-run ./setup.sh"
      exit 1
      ;;
  esac
fi

if ! python3 -c 'import argparse, dataclasses, pathlib, subprocess' >/dev/null 2>&1; then
  echo "python3 is missing required standard-library modules."
  exit 1
fi

export YF_DISTRO="$DISTRO"
export PYTHONPATH="$REPO_DIR${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m provision.main "$@"
