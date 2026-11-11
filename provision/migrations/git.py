"""Git feature migrations."""

from __future__ import annotations

import tempfile
from pathlib import Path

from ..common import apt_install, dnf_install, distro_id, run, cmd_exists
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro

    def install_gh_cli_up() -> None:
        if install_gh_cli_check():
            print("gh already installed (external) - recording migration")
            return
        if distro in {"debian", "ubuntu"}:
            run(["sudo", "mkdir", "-p", "-m", "755", "/etc/apt/keyrings"])
            fd, out = tempfile.mkstemp()
            import os
            os.close(fd)
            run(["wget", "-nv", "-O", out, "https://cli.github.com/packages/githubcli-archive-keyring.gpg"])
            run(["sudo", "cp", out, "/etc/apt/keyrings/githubcli-archive-keyring.gpg"])
            run(["sudo", "chmod", "go+r", "/etc/apt/keyrings/githubcli-archive-keyring.gpg"])
            Path(out).unlink(missing_ok=True)
            arch = run(["dpkg", "--print-architecture"], capture=True).stdout.strip()
            line = f"deb [arch={arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages/deb stable main"
            run(["sudo", "bash", "-c", f"printf '%s\\n' '{line}' > /etc/apt/sources.list.d/github-cli.list"])
            apt_install(["gh"])
        elif distro == "fedora":
            run(["sudo", "dnf", "install", "-y", "dnf-command(config-manager)"])
            run(["sudo", "dnf", "config-manager", "addrepo", "--from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo"])
            run(["sudo", "dnf", "install", "-y", "gh", "--repo", "gh-cli"])
        else:
            print(f"WARNING: unsupported distro {distro}")

    def install_gh_cli_down() -> None:
        if ctx.purge:
            if distro in {"debian", "ubuntu"}:
                run(["sudo", "apt", "remove", "-y", "gh"], check=False)
                run(["sudo", "rm", "-f", "/etc/apt/keyrings/githubcli-archive-keyring.gpg"], check=False)
                run(["sudo", "rm", "-f", "/etc/apt/sources.list.d/github-cli.list"], check=False)
            elif distro == "fedora":
                run(["sudo", "dnf", "remove", "-y", "gh"], check=False)
                run(["sudo", "rm", "-f", "/etc/yum.repos.d/gh-cli.repo"], check=False)
        elif cmd_exists("gh"):
            print("NOTE: gh remains (run with --purge to remove).")

    def install_gh_cli_check() -> bool:
        return cmd_exists("gh")

    return [
        Migration("install_gh_cli", "git", install_gh_cli_up, install_gh_cli_down, install_gh_cli_check),
    ]
