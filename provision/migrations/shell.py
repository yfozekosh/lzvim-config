"""Shell feature migrations."""

from __future__ import annotations

import shutil
import tarfile
import tempfile
from pathlib import Path

from ..common import append_line, download_file, remove_line
from ..models import Migration, SetupContext

BLESH_VERSION = "0.3.4"
BLESH_URL = f"https://github.com/akinomyoga/ble.sh/releases/download/v{BLESH_VERSION}/ble-{BLESH_VERSION}.tar.xz"
BLESH_SHA256 = "e543a43d211fef8f52b96b2e7935e892581421f759cda4ae87563854ebc60573"


def build(ctx: SetupContext) -> list[Migration]:
    home = ctx.home

    def bashrc_source_up() -> None:
        line = "source ~/.bash_profile_yf"
        bashrc = home / ".bashrc"
        if not (bashrc.is_file() and line in bashrc.read_text(encoding="utf-8").splitlines()):
            append_line(bashrc, line)

    def bashrc_source_down() -> None:
        remove_line(home / ".bashrc", "source ~/.bash_profile_yf")

    def bashrc_source_check() -> bool:
        return (home / ".bashrc").is_file() and "source ~/.bash_profile_yf" in (home / ".bashrc").read_text(encoding="utf-8").splitlines()

    def install_blesh_up() -> None:
        if install_blesh_check():
            print("ble.sh already installed (external) - recording migration")
            return
        blesh_dir = home / ".local" / "share" / "blesh"
        with tempfile.TemporaryDirectory(prefix="yf-blesh-") as tmp:
            tmp_dir = Path(tmp)
            archive = tmp_dir / f"ble-{BLESH_VERSION}.tar.xz"
            download_file(BLESH_URL, archive, BLESH_SHA256)
            with tarfile.open(archive, "r:xz") as tar:
                tar.extractall(tmp_dir)
            source = tmp_dir / f"ble-{BLESH_VERSION}"
            if not (source / "ble.sh").is_file():
                raise RuntimeError(f"unexpected ble.sh archive layout: {source}")
            if blesh_dir.exists():
                shutil.rmtree(blesh_dir)
            blesh_dir.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(source, blesh_dir)
        line = "source -- ~/.local/share/blesh/ble.sh"
        bashrc = home / ".bashrc"
        if not (bashrc.is_file() and line in bashrc.read_text(encoding="utf-8").splitlines()):
            append_line(bashrc, line)

    def install_blesh_down() -> None:
        shutil.rmtree(home / ".local" / "share" / "blesh", ignore_errors=True)
        remove_line(home / ".bashrc", "source -- ~/.local/share/blesh/ble.sh")

    def install_blesh_check() -> bool:
        line = "source -- ~/.local/share/blesh/ble.sh"
        bashrc = home / ".bashrc"
        return (home / ".local" / "share" / "blesh" / "ble.sh").is_file() and (
            bashrc.is_file() and line in bashrc.read_text(encoding="utf-8").splitlines()
        )

    return [
        Migration("bashrc_source", "shell", bashrc_source_up, bashrc_source_down, bashrc_source_check),
        Migration("install_blesh", "shell", install_blesh_up, install_blesh_down, install_blesh_check),
    ]
