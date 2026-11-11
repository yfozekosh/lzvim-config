"""Core feature migrations."""

from __future__ import annotations

from ..common import (
    apt_install,
    dnf_install,
    ensure_symlink,
    remove_symlink_if_points_to,
    run,
    sudo,
    cmd_exists,
)
from ..models import Migration, SetupContext


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

    def ensure_config_symlinks() -> None:
        ensure_symlink(repo / ".tmux.conf", home / ".tmux.conf")
        ensure_symlink(repo / ".bash_profile_yf", home / ".bash_profile_yf")
        ensure_symlink(repo / ".blerc", home / ".blerc")
        ensure_symlink(repo / ".gdbinit", home / ".gdbinit")
        ensure_symlink(repo / "tmux-scripts", home / ".tmux" / "scripts")
        ensure_symlink(repo / "copilot-instructions.md", home / ".copilot" / "copilot-instructions.md")
        ensure_symlink(repo / "asm-lsp" / ".asm-lsp.toml", home / ".config" / "asm-lsp" / ".asm-lsp.toml")
        ensure_symlink(repo / "scripts" / "ld-format", home / ".local" / "bin" / "ld-format")

    def link_configs_up() -> None:
        ensure_config_symlinks()

    def link_configs_down() -> None:
        targets = [
            (home / ".tmux.conf", repo / ".tmux.conf"),
            (home / ".bash_profile_yf", repo / ".bash_profile_yf"),
            (home / ".blerc", repo / ".blerc"),
            (home / ".gdbinit", repo / ".gdbinit"),
            (home / ".tmux" / "scripts", repo / "tmux-scripts"),
            (home / ".copilot" / "copilot-instructions.md", repo / "copilot-instructions.md"),
            (home / ".config" / "asm-lsp" / ".asm-lsp.toml", repo / "asm-lsp" / ".asm-lsp.toml"),
            (home / ".local" / "bin" / "ld-format", repo / "scripts" / "ld-format"),
        ]
        for link, target in targets:
            remove_symlink_if_points_to(link, target)

    def link_configs_check() -> bool:
        return (home / ".tmux.conf").is_symlink()

    def repair_symlinks_up() -> None:
        ensure_config_symlinks()

    def repair_symlinks_down() -> None:
        pass

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
        return (home / ".local" / "share" / "nvim" / "lazy").is_dir()

    return [
        Migration("install_packages", "core", install_packages_up, install_packages_down, install_packages_check),
        Migration("link_configs", "core", link_configs_up, link_configs_down, link_configs_check),
        Migration(
            "repair_config_symlinks",
            "core",
            repair_symlinks_up,
            repair_symlinks_down,
            lambda: True,
            always=True,
        ),
        Migration("install_lazygit", "core", install_lazygit_up, install_lazygit_down, install_lazygit_check),
        Migration(
            "bootstrap_nvim_plugins",
            "core",
            bootstrap_nvim_plugins_up,
            bootstrap_nvim_plugins_down,
            bootstrap_nvim_plugins_check,
        ),
    ]
