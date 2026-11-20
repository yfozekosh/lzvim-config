"""Neovim feature migrations."""

from __future__ import annotations

from pathlib import Path

from ..common import run
from ..models import Migration, SetupContext


def nvim_plugins_bootstrapped(home: Path, rpi_marker: Path = Path("/etc/rpi-issue")) -> bool:
    """Raspberry Pi runs the plugin-free config; there is nothing to sync."""
    if rpi_marker.is_file():
        return True
    return (home / ".local" / "share" / "nvim" / "lazy").is_dir()


def build(ctx: SetupContext) -> list[Migration]:
    repo = ctx.repo
    home = ctx.home

    def bootstrap_nvim_plugins_up() -> None:
        if bootstrap_nvim_plugins_check():
            print("nvim plugins already bootstrapped (external) - recording migration")
            return
        run(["nvim", "--headless", "-c", f"luafile {repo / 'scripts' / 'headless_bootstrap.lua'}"])

    def bootstrap_nvim_plugins_down() -> None:
        pass

    def bootstrap_nvim_plugins_check() -> bool:
        return nvim_plugins_bootstrapped(home)

    def prune_nvim_state_up() -> None:
        # Runs every setup: removes lazy plugins, Mason packages and
        # treesitter parsers the current profile no longer declares (e.g.
        # clangd after deselecting `clangd`). Needs the plugins installed
        # by bootstrap_nvim_plugins; skipped on Raspberry Pi (plugin-free).
        if Path("/etc/rpi-issue").is_file():
            return
        if not (home / ".local" / "share" / "nvim" / "lazy").is_dir():
            return
        run(["nvim", "--headless", "-c", f"luafile {repo / 'scripts' / 'headless_prune.lua'}"], check=False)

    def prune_nvim_state_down() -> None:
        pass

    return [
        Migration(
            "bootstrap_nvim_plugins",
            "nvim",
            bootstrap_nvim_plugins_up,
            bootstrap_nvim_plugins_down,
            bootstrap_nvim_plugins_check,
        ),
        Migration(
            "prune_nvim_state",
            "nvim",
            prune_nvim_state_up,
            prune_nvim_state_down,
            lambda: True,
            always=True,
        ),
    ]
