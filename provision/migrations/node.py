"""Node.js feature migrations.

Both ``ai`` (Copilot CLI) and ``frontend`` (TypeScript/Angular/Prettier
tooling) depend on this feature, so a frontend-only profile gets Node without
pulling in Copilot or the Claude status line.
"""

from __future__ import annotations

from ..common import apt_install, cmd_exists, dnf_install, run, sudo
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro

    def install_nodejs_up() -> None:
        if cmd_exists("node") and cmd_exists("npm"):
            print("node/npm already installed (external) - recording migration")
            return
        if distro in {"debian", "ubuntu"}:
            apt_install(["nodejs", "npm"])
        elif distro == "fedora":
            dnf_install(["nodejs", "npm"])
        else:
            raise RuntimeError(f"unsupported distro: {distro}")

    def install_nodejs_down() -> None:
        if ctx.purge:
            if distro in {"debian", "ubuntu"}:
                run(sudo(["apt", "remove", "-y", "nodejs", "npm"]), check=False)
            elif distro == "fedora":
                run(sudo(["dnf", "remove", "-y", "nodejs", "npm"]), check=False)
        elif cmd_exists("node") or cmd_exists("npm"):
            print("NOTE: node/npm remains (run with --purge to remove).")

    def install_nodejs_check() -> bool:
        return cmd_exists("node") and cmd_exists("npm")

    return [
        Migration("install_nodejs", "node", install_nodejs_up, install_nodejs_down, install_nodejs_check),
    ]
