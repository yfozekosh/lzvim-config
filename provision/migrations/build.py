"""Build-toolchain feature migrations.

These are deliberately separate from ``core``: work/frontend/dotnet profiles
do not need a C++ compiler or CMake.  ``core`` still installs ``gcc`` because
Neovim's Treesitter parser builds require a working ``cc``.
"""

from __future__ import annotations

from ..common import apt_install, cmd_exists, dnf_install, run, sudo
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro

    def install_cmake_up() -> None:
        if install_cmake_check():
            print("cmake already installed (external) - recording migration")
            return
        if distro in {"debian", "ubuntu"}:
            apt_install(["cmake"])
        elif distro == "fedora":
            dnf_install(["cmake"])
        else:
            raise RuntimeError(f"unsupported distro: {distro}")

    def install_cmake_down() -> None:
        if ctx.purge and cmd_exists("cmake"):
            if distro in {"debian", "ubuntu"}:
                run(sudo(["apt", "remove", "-y", "cmake"]), check=False)
            elif distro == "fedora":
                run(sudo(["dnf", "remove", "-y", "cmake"]), check=False)
        elif cmd_exists("cmake"):
            print("NOTE: cmake remains (run with --purge to remove).")

    def install_cmake_check() -> bool:
        return cmd_exists("cmake")

    def install_build_essentials_up() -> None:
        if install_build_essentials_check():
            print("C++ build tools already installed (external) - recording migration")
            return
        if distro == "fedora":
            dnf_install(["gcc-c++", "make"])
        elif distro in {"debian", "ubuntu"}:
            # build-essential provides g++, make, and libc development headers.
            apt_install(["build-essential"])
        else:
            raise RuntimeError(f"unsupported distro: {distro}")

    def install_build_essentials_down() -> None:
        if ctx.purge:
            if distro == "fedora":
                run(sudo(["dnf", "remove", "-y", "gcc-c++", "make"]), check=False)
            elif distro in {"debian", "ubuntu"}:
                run(sudo(["apt", "remove", "-y", "build-essential"]), check=False)
        elif cmd_exists("g++") or cmd_exists("c++"):
            print("NOTE: C++ build tools remain (run with --purge to remove).")

    def install_build_essentials_check() -> bool:
        return (cmd_exists("g++") or cmd_exists("c++")) and cmd_exists("make")

    return [
        Migration("install_cmake", "build", install_cmake_up, install_cmake_down, install_cmake_check),
        Migration(
            "install_build_essentials",
            "build",
            install_build_essentials_up,
            install_build_essentials_down,
            install_build_essentials_check,
        ),
    ]
