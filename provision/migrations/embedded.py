"""Embedded feature migrations."""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

from ..common import run, cmd_exists, distro_id, apt_install, dnf_install
from ..models import Migration, SetupContext

ASMLSP_COMMIT = "bacbe5eedfbfc202afe8f517faef2d5b9152bf95"
RVFMT_COMMIT = "9247d1b9d85ffb9e6e38a12e15f295b084e6014b"


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro
    repo = ctx.repo
    home = ctx.home

    def ensure_cargo() -> bool:
        if cmd_exists("cargo"):
            return True
        cargo_bin = home / ".cargo" / "bin" / "cargo"
        if cargo_bin.is_file():
            import os
            os.environ["PATH"] = f"{home / '.cargo' / 'bin'}:{os.environ.get('PATH', '')}"
            return True
        if distro in {"debian", "ubuntu"}:
            apt_install(["cargo"])
        elif distro == "fedora":
            dnf_install(["cargo"])
        else:
            print(f"WARNING: cannot install cargo on {distro}")
            return False
        return cmd_exists("cargo")

    def install_riscv_asm_tools_up() -> None:
        if install_riscv_asm_tools_check():
            print("RISC-V asm tools already installed (external) - recording migration")
            return
        bin_dir = home / ".local" / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        import os
        os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}"

        asm_lsp = bin_dir / "asm-lsp"
        if not asm_lsp.is_file():
            if ensure_cargo():
                tmp = Path(tempfile.mkdtemp())
                try:
                    run(["git", "clone", "https://github.com/bergercookie/asm-lsp.git", str(tmp / "asm-lsp")])
                    run(["git", "-C", str(tmp / "asm-lsp"), "checkout", "--detach", ASMLSP_COMMIT])
                    patch = repo / "patches" / "asm-lsp-full-reparse.patch"
                    if patch.is_file():
                        run(["git", "-C", str(tmp / "asm-lsp"), "apply", str(patch)])
                    run(["cargo", "install", "--path", "asm-lsp", "--root", str(home / ".local"), "--locked"], cwd=tmp / "asm-lsp", check=False)
                finally:
                    shutil.rmtree(tmp, ignore_errors=True)
            else:
                print("WARNING: cargo unavailable - skipping asm-lsp.")

        rvfmt = bin_dir / "rvfmt"
        if not rvfmt.is_file():
            if ensure_cargo():
                tmp = Path(tempfile.mkdtemp())
                try:
                    run(["git", "clone", "https://github.com/mattfbacon/riscv-asm-fmt.git", str(tmp / "riscv-asm-fmt")])
                    run(["git", "-C", str(tmp / "riscv-asm-fmt"), "checkout", "--detach", RVFMT_COMMIT])
                    patch = repo / "patches" / "riscv-asm-fmt-dollar-symbol.patch"
                    if patch.is_file():
                        run(["git", "-C", str(tmp / "riscv-asm-fmt"), "apply", str(patch)])
                    run(["cargo", "install", "--path", "cli", "--root", str(home / ".local"), "--locked"], cwd=tmp / "riscv-asm-fmt", check=False)
                finally:
                    shutil.rmtree(tmp, ignore_errors=True)
            else:
                print("WARNING: cargo unavailable - skipping rvfmt.")

        if not asm_lsp.is_file() or not rvfmt.is_file():
            print("WARNING: RISC-V asm tooling incomplete.")

    def install_riscv_asm_tools_down() -> None:
        (home / ".local" / "bin" / "asm-lsp").unlink(missing_ok=True)
        (home / ".local" / "bin" / "rvfmt").unlink(missing_ok=True)

    def install_riscv_asm_tools_check() -> bool:
        return (home / ".local" / "bin" / "asm-lsp").is_file() and (home / ".local" / "bin" / "rvfmt").is_file()

    return [
        Migration("install_riscv_asm_tools", "embedded", install_riscv_asm_tools_up, install_riscv_asm_tools_down, install_riscv_asm_tools_check),
    ]
