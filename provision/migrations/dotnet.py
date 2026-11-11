"""Dotnet feature migrations."""

from __future__ import annotations

import shutil
from ..common import cmd_exists, run, sudo
from ..models import Migration, SetupContext


def _installed_dotnet_packages(distro: str) -> list[str]:
    if distro == "fedora":
        result = run(["rpm", "-qa", "--qf", "%{NAME}\n"], check=False, capture=True)
    elif distro in {"debian", "ubuntu"}:
        result = run(["dpkg-query", "-W", "-f=${Package}\n", "dotnet-*"], check=False, capture=True)
    else:
        return []
    if result.returncode != 0:
        return []
    return sorted({line.strip() for line in result.stdout.splitlines() if line.strip().startswith("dotnet-")})


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro
    home = ctx.home

    def install_dotnet_up() -> None:
        if cmd_exists("dotnet"):
            print("dotnet already installed (external) - recording migration")
            return
        if distro in {"fedora"}:
            run(["sudo", "dnf", "install", "-y", "glibc", "libgcc", "ca-certificates", "openssl-libs", "libstdc++", "libicu", "tzdata", "krb5-libs", "zlib"])
        elif distro in {"debian", "ubuntu"}:
            run(["sudo", "apt", "install", "-y", "libc6", "libgcc-s1", "ca-certificates", "openssl", "libstdc++6", "libicu-dev", "tzdata", "zlib1g"])
        else:
            print(f"WARNING: unsupported distro {distro}")
        installer = home / "dotnet-install.sh"
        run(["wget", "https://dot.net/v1/dotnet-install.sh", "-O", str(installer)])
        run(["chmod", "+x", str(installer)])
        run([str(installer)])

    def install_dotnet_down() -> None:
        # Remove the user-level SDK installed by dotnet-install.sh.
        shutil.rmtree(home / ".dotnet", ignore_errors=True)
        (home / "dotnet-install.sh").unlink(missing_ok=True)

        # Also remove system packages (dotnet-sdk, dotnet-runtime, dotnet-host,
        # ...). The dotnet feature owns the CLI, so unchecking it should not
        # leave `dotnet` available.
        packages = _installed_dotnet_packages(distro)
        if packages:
            print(f"Removing system dotnet packages: {', '.join(packages)}")
            if distro == "fedora":
                run(sudo(["dnf", "remove", "-y", *packages]), check=False)
            else:
                run(sudo(["apt", "remove", "-y", *packages]), check=False)

        if shutil.which("dotnet"):
            print("NOTE: dotnet is still on PATH (installed via another method); remove it manually if desired.")

    def install_dotnet_check() -> bool:
        return cmd_exists("dotnet")

    return [
        Migration("install_dotnet", "dotnet", install_dotnet_up, install_dotnet_down, install_dotnet_check),
    ]
