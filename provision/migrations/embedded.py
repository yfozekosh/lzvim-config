"""RISC-V assembly feature migrations (clangd is editor-only)."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

from ..common import run, cmd_exists, apt_install, dnf_install
from ..links import ConfigLink, link_migration
from ..models import Migration, SetupContext

ASMLSP_COMMIT = "bacbe5eedfbfc202afe8f517faef2d5b9152bf95"
RVFMT_COMMIT = "9247d1b9d85ffb9e6e38a12e15f295b084e6014b"


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro
    repo = ctx.repo
    home = ctx.home
    bin_dir = home / ".local" / "bin"

    def ensure_cargo() -> bool:
        if cmd_exists("cargo"):
            return True
        cargo_bin = home / ".cargo" / "bin" / "cargo"
        if cargo_bin.is_file():
            os.environ["PATH"] = f"{home / '.cargo' / 'bin'}:{os.environ.get('PATH', '')}"
            return True
        print("cargo not found; installing cargo to build the RISC-V asm tools.")
        if distro in {"debian", "ubuntu"}:
            apt_install(["cargo"])
        elif distro == "fedora":
            dnf_install(["cargo"])
        else:
            print(f"WARNING: cannot install cargo on {distro}")
            return False
        return cmd_exists("cargo")

    def prepare_bin_dir() -> None:
        bin_dir.mkdir(parents=True, exist_ok=True)
        os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}"

    def install_asm_lsp_up() -> None:
        if install_asm_lsp_check():
            print("asm-lsp already installed (external) - recording migration")
            return
        if not ensure_cargo():
            print("WARNING: cargo unavailable - skipping asm-lsp.")
            return
        prepare_bin_dir()
        tmp = Path(tempfile.mkdtemp())
        try:
            run(["git", "clone", "https://github.com/bergercookie/asm-lsp.git", str(tmp / "asm-lsp")])
            run(["git", "-C", str(tmp / "asm-lsp"), "checkout", "--detach", ASMLSP_COMMIT])
            patch = repo / "patches" / "asm-lsp-full-reparse.patch"
            if patch.is_file():
                run(["git", "-C", str(tmp / "asm-lsp"), "apply", str(patch)])
            run(
                ["cargo", "install", "--path", "asm-lsp", "--root", str(home / ".local"), "--locked"],
                cwd=tmp / "asm-lsp",
                check=False,
            )
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if not (bin_dir / "asm-lsp").is_file():
            print("WARNING: asm-lsp installation failed.")

    def install_asm_lsp_down() -> None:
        (bin_dir / "asm-lsp").unlink(missing_ok=True)

    def install_asm_lsp_check() -> bool:
        return (bin_dir / "asm-lsp").is_file()

    def install_rvfmt_up() -> None:
        if install_rvfmt_check():
            print("rvfmt already installed (external) - recording migration")
            return
        if not ensure_cargo():
            print("WARNING: cargo unavailable - skipping rvfmt.")
            return
        prepare_bin_dir()
        tmp = Path(tempfile.mkdtemp())
        try:
            run(["git", "clone", "https://github.com/mattfbacon/riscv-asm-fmt.git", str(tmp / "riscv-asm-fmt")])
            run(["git", "-C", str(tmp / "riscv-asm-fmt"), "checkout", "--detach", RVFMT_COMMIT])
            patch = repo / "patches" / "riscv-asm-fmt-dollar-symbol.patch"
            if patch.is_file():
                run(["git", "-C", str(tmp / "riscv-asm-fmt"), "apply", str(patch)])
            run(
                ["cargo", "install", "--path", "cli", "--root", str(home / ".local"), "--locked"],
                cwd=tmp / "riscv-asm-fmt",
                check=False,
            )
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if not (bin_dir / "rvfmt").is_file():
            print("WARNING: rvfmt installation failed.")

    def install_rvfmt_down() -> None:
        (bin_dir / "rvfmt").unlink(missing_ok=True)

    def install_rvfmt_check() -> bool:
        return (bin_dir / "rvfmt").is_file()

    return [
        Migration("install_asm_lsp", "riscv-asm", install_asm_lsp_up, install_asm_lsp_down, install_asm_lsp_check),
        Migration("install_rvfmt", "riscv-asm", install_rvfmt_up, install_rvfmt_down, install_rvfmt_check),
        link_migration(
            "link_riscv_asm_configs",
            "riscv-asm",
            [
                ConfigLink(
                    repo / "asm-lsp" / ".asm-lsp.toml",
                    home / ".config" / "asm-lsp" / ".asm-lsp.toml",
                ),
                ConfigLink(repo / "scripts" / "ld-format", home / ".local" / "bin" / "ld-format"),
            ],
        ),
    ]
