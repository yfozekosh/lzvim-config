"""Core feature migrations."""

from __future__ import annotations

from pathlib import Path

from ..common import (
    apt_install,
    dnf_install,
    run,
    sudo,
    cmd_exists,
)
from ..models import Migration, SetupContext


def nvim_plugins_bootstrapped(home: Path, rpi_marker: Path = Path("/etc/rpi-issue")) -> bool:
    """Raspberry Pi runs the plugin-free config; there is nothing to sync."""
    if rpi_marker.is_file():
        return True
    return (home / ".local" / "share" / "nvim" / "lazy").is_dir()


def build(ctx: SetupContext) -> list[Migration]:
    repo = ctx.repo
    home = ctx.home
    distro = ctx.distro

    def install_packages_up() -> None:
        if install_packages_check():
            print("packages already installed (external) - recording migration")
            return
        if distro in {"debian", "ubuntu"}:
            apt_install(["tmux", "git", "gcc", "neovim", "bat", "fastfetch", "vim", "wget", "curl", "xz-utils", "gawk", "unzip"])
        elif distro == "fedora":
            dnf_install(["tmux", "git", "gcc", "neovim", "bat", "fastfetch", "vim", "wget", "curl", "xz", "gawk", "unzip"])
        else:
            raise RuntimeError(f"unsupported distro: {distro}")

    def install_packages_down() -> None:
        if ctx.purge:
            common = ["tmux", "git", "gcc", "neovim", "bat", "fastfetch", "vim", "wget", "curl", "gawk", "unzip"]
            if distro in {"debian", "ubuntu"}:
                run(sudo(["apt", "remove", "-y", *common, "xz-utils"]), check=False)
            elif distro == "fedora":
                run(sudo(["dnf", "remove", "-y", *common, "xz"]), check=False)
        else:
            if cmd_exists("nvim") or cmd_exists("tmux") or cmd_exists("git"):
                print("NOTE: core packages may remain (run with --purge to remove OS packages).")

    def install_packages_check() -> bool:
        return (
            cmd_exists("nvim")
            and cmd_exists("tmux")
            and cmd_exists("git")
            and (cmd_exists("gcc") or cmd_exists("cc"))
        )

    def install_lazygit_up() -> None:
        if install_lazygit_check():
            print("lazygit already installed (external) - recording migration")
            return
        if distro == "fedora":
            run(["dnf", "copr", "enable", "-y", "atim/lazygit"])
            dnf_install(["lazygit"])
        else:
            print("WARNING: install_lazygit only supports Fedora; install manually.")

    def install_lazygit_down() -> None:
        if ctx.purge and distro == "fedora":
            run(sudo(["dnf", "remove", "-y", "lazygit"]), check=False)
            run(sudo(["dnf", "copr", "disable", "-y", "atim/lazygit"]), check=False)
        elif cmd_exists("lazygit"):
            print("NOTE: lazygit remains (run with --purge to remove).")

    def install_lazygit_check() -> bool:
        return cmd_exists("lazygit")

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
        # clangd after deselecting `embedded`). Needs the plugins installed
        # by bootstrap_nvim_plugins; skipped on Raspberry Pi (plugin-free).
        if Path("/etc/rpi-issue").is_file():
            return
        if not (home / ".local" / "share" / "nvim" / "lazy").is_dir():
            return
        run(["nvim", "--headless", "-c", f"luafile {repo / 'scripts' / 'headless_prune.lua'}"], check=False)

    def prune_nvim_state_down() -> None:
        pass

    return [
        Migration("install_packages", "core", install_packages_up, install_packages_down, install_packages_check),
        Migration("install_lazygit", "core", install_lazygit_up, install_lazygit_down, install_lazygit_check),
        Migration(
            "bootstrap_nvim_plugins",
            "core",
            bootstrap_nvim_plugins_up,
            bootstrap_nvim_plugins_down,
            bootstrap_nvim_plugins_check,
        ),
        Migration(
            "prune_nvim_state",
            "core",
            prune_nvim_state_up,
            prune_nvim_state_down,
            lambda: True,
            always=True,
        ),
    ]
