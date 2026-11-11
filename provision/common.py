"""Shared helpers for the setup orchestrator."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import urllib.request
from pathlib import Path
from typing import Iterable, Sequence


class CommandError(RuntimeError):
    """Raised when a subprocess exits non-zero."""


def run(
    args: Sequence[str],
    *,
    check: bool = True,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run a command, optionally raising on failure."""
    result = subprocess.run(
        list(args),
        cwd=str(cwd) if cwd is not None else None,
        env=env,
        text=True,
        capture_output=capture,
        check=False,
    )
    if check and result.returncode != 0:
        raise CommandError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"stdout: {result.stdout or ''}\nstderr: {result.stderr or ''}"
        )
    return result


def cmd_exists(name: str) -> bool:
    """Return True if an executable is on PATH."""
    return shutil.which(name) is not None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_file(url: str, destination: Path, expected_sha256: str) -> None:
    """Download a pinned artifact and verify its SHA-256 checksum."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=30) as response, destination.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    actual = sha256_file(destination)
    if actual != expected_sha256:
        destination.unlink(missing_ok=True)
        raise CommandError(f"checksum mismatch for {url}: expected {expected_sha256}, got {actual}")


def is_wsl() -> bool:
    """Detect WSL via /proc/version."""
    try:
        text = Path("/proc/version").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return "microsoft" in text.lower()


def distro_id() -> str:
    """Read ID from /etc/os-release."""
    os_release = Path("/etc/os-release")
    if not os_release.is_file():
        return "unknown"
    for line in os_release.read_text(encoding="utf-8").splitlines():
        if line.startswith("ID="):
            return line.split("=", 1)[1].strip().strip('"').lower()
    return "unknown"


def sudo(cmd: Sequence[str]) -> list[str]:
    """Prefix with sudo unless already root."""
    if os.geteuid() == 0:
        return list(cmd)
    return ["sudo", *cmd]


def apt_install(packages: Iterable[str]) -> None:
    run(sudo(["apt", "update"]))
    run(sudo(["apt", "install", "-y", *packages]))


def dnf_install(packages: Iterable[str]) -> None:
    run(sudo(["dnf", "install", "-y", *packages]))


def ensure_symlink(target: Path, link: Path) -> None:
    """Create/repair a symlink, only touching it when needed."""
    link.parent.mkdir(parents=True, exist_ok=True)
    current = None
    try:
        current = link.readlink()
    except OSError:
        current = None
    if current != target:
        if link.exists() or link.is_symlink():
            if link.is_dir() and not link.is_symlink():
                raise CommandError(f"refusing to replace non-symlink directory: {link}")
            link.unlink()
        link.symlink_to(target)


def remove_symlink_if_points_to(link: Path, target: Path) -> bool:
    """Remove a symlink only if it points at target. Returns True if removed."""
    try:
        current = link.readlink()
    except OSError:
        return False
    if current == target:
        link.unlink()
        return True
    return False


def grep_line(path: Path, needle: str) -> bool:
    """Return True if an exact line exists in path."""
    if not path.is_file():
        return False
    return needle in path.read_text(encoding="utf-8").splitlines()


def append_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def remove_line(path: Path, line: str) -> bool:
    """Remove all exact occurrences of line. Returns True if changed."""
    if not path.is_file():
        return False
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    kept = [item for item in lines if item.rstrip("\n") != line]
    if len(kept) == len(lines):
        return False
    path.write_text("".join(kept), encoding="utf-8")
    return True


def pkg_installed_debian(package: str) -> bool:
    result = run(["dpkg", "-s", package], check=False, capture=True)
    return result.returncode == 0


def pkg_installed_fedora(package: str) -> bool:
    result = run(["rpm", "-q", package], check=False, capture=True)
    return result.returncode == 0
