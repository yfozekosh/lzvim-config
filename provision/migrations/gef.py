"""GEF fork migrations."""

from __future__ import annotations

import shutil
from pathlib import Path

from ..common import run
from ..models import Migration, SetupContext

GEF_REPO = "https://github.com/yfozekosh/gef.git"
GEF_BRANCH = "ch32v003-rv32ec"
GEF_REMOTES = {
    GEF_REPO,
    "https://github.com/yfozekosh/gef",
    "git@github.com:yfozekosh/gef.git",
    "git@github.com:yfozekosh/gef",
    "ssh://git@github.com/yfozekosh/gef.git",
}


def is_installed(target: Path) -> bool:
    """True when both scripts from the fork are present at target."""
    return (target / "gef.py").is_file() and (target / "gef_riscv.py").is_file()


def is_our_checkout(target: Path) -> bool:
    """True only for a real clone of the GEF fork, never for a symlink."""
    if target.is_symlink() or not target.is_dir():
        return False
    if not (target / ".git").is_dir():
        return False
    try:
        result = run(
            ["git", "-C", str(target), "remote", "get-url", "origin"],
            check=False,
            capture=True,
        )
    except OSError:
        return False
    return result.returncode == 0 and result.stdout.strip() in GEF_REMOTES


def build(ctx: SetupContext) -> list[Migration]:
    target = ctx.home / ".local" / "share" / "gef"

    def install_gef_up() -> None:
        if is_installed(target):
            print(f"GEF fork already installed at {target} (external) - recording migration")
            return
        if target.is_symlink():
            print(f"WARNING: {target} is a symlink but does not contain the GEF fork; leaving it alone.")
            return
        if target.exists():
            print(
                f"WARNING: {target} exists but does not contain the GEF fork; "
                "remove or repair it, then re-run setup."
            )
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--branch", GEF_BRANCH, "--depth", "1", GEF_REPO, str(target)])
        if not is_installed(target):
            print(
                f"WARNING: cloned {GEF_REPO} but {target / 'gef.py'} or "
                f"{target / 'gef_riscv.py'} is missing."
            )

    def install_gef_down() -> None:
        if target.is_symlink():
            print(f"NOTE: {target} is a symlink to a development checkout; leaving it in place.")
            return
        if not target.exists():
            return
        if not is_our_checkout(target):
            print(f"NOTE: {target} is not a clone of {GEF_REPO}; leaving it in place.")
            return
        shutil.rmtree(target)
        # Remove the now-empty parent only when nothing else lives there.
        try:
            target.parent.rmdir()
        except OSError:
            pass

    return [
        Migration(
            "install_gef",
            "gef",
            install_gef_up,
            install_gef_down,
            lambda: is_installed(target),
        ),
    ]
