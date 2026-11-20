"""Core feature migrations."""

from __future__ import annotations

from ..common import (
    apt_install,
    dnf_install,
    run,
    sudo,
    cmd_exists,
)
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
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

    return [
        Migration("install_packages", "core", install_packages_up, install_packages_down, install_packages_check),
    ]
