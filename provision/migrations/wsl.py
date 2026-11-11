"""WSL feature migrations."""

from __future__ import annotations

from pathlib import Path

from ..common import apt_install, dnf_install, distro_id, run, cmd_exists
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro
    home = ctx.home

    def install_wsl_fonts_up() -> None:
        if install_wsl_fonts_check():
            print("WSL fonts already installed (external) - recording migration")
            return
        if distro in {"debian", "ubuntu"}:
            apt_install(["fonts-dejavu", "fonts-liberation"])
        elif distro == "fedora":
            dnf_install(["dejavu-fonts-all", "liberation-fonts-all"])
        else:
            print(f"WARNING: unsupported distro {distro}")
            return
        run(["fc-cache", "-f"], check=False)

    def install_wsl_fonts_down() -> None:
        if ctx.purge:
            if distro in {"debian", "ubuntu"}:
                run(["sudo", "apt", "remove", "-y", "fonts-dejavu", "fonts-liberation"], check=False)
            elif distro == "fedora":
                run(["sudo", "dnf", "remove", "-y", "dejavu-fonts-all", "liberation-fonts-all"], check=False)
        else:
            print("NOTE: WSL fonts remain (run with --purge to remove).")

    def install_wsl_fonts_check() -> bool:
        return Path("/usr/share/fonts/dejavu").exists() or Path("/usr/share/fonts/truetype/dejavu").exists()

    def install_win32yank_up() -> None:
        import tempfile, zipfile
        bin_dir = home / ".local" / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        target = bin_dir / "win32yank.exe"
        if target.is_file():
            print("win32yank already present (external) - recording migration")
            return
        tmp = Path(tempfile.mkdtemp())
        try:
            zip_path = tmp / "win32yank.zip"
            run(["curl", "-fsSL", "-o", str(zip_path), "https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip"])
            with zipfile.ZipFile(zip_path) as zf:
                zf.extract("win32yank.exe", tmp)
            (tmp / "win32yank.exe").replace(target)
            target.chmod(0o755)
        finally:
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)

    def install_win32yank_down() -> None:
        (home / ".local" / "bin" / "win32yank.exe").unlink(missing_ok=True)

    def install_win32yank_check() -> bool:
        return (home / ".local" / "bin" / "win32yank.exe").is_file()

    def read_wsl_conf() -> str:
        conf = Path("/etc/wsl.conf")
        try:
            return conf.read_text(encoding="utf-8")
        except PermissionError:
            result = run(["sudo", "cat", str(conf)], check=False, capture=True)
            return result.stdout if result.returncode == 0 else ""
        except OSError:
            return ""

    def write_wsl_conf(content: str) -> None:
        import tempfile
        conf = Path("/etc/wsl.conf")
        tmp_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
                handle.write(content)
                tmp_path = Path(handle.name)
            run(["sudo", "cp", str(tmp_path), str(conf)])
            run(["sudo", "chmod", "644", str(conf)])
        finally:
            if tmp_path is not None:
                tmp_path.unlink(missing_ok=True)

    def fix_wsl_interop_persistence_up() -> None:
        run(["sudo", "touch", "/etc/wsl.conf"])
        content = read_wsl_conf()
        if "WSLInterop:M::MZ::/init" in content:
            print("wsl.conf already has the WSLInterop boot command, skipping.")
            return
        cmd_line = 'command="echo \':WSLInterop:M::MZ::/init:PF\' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true"'
        if "[boot]" in content:
            lines = content.splitlines()
            out = []
            done = False
            for line in lines:
                out.append(line)
                if line.strip() == "[boot]" and not done:
                    out.append(cmd_line)
                    done = True
            write_wsl_conf("\n".join(out) + "\n")
        else:
            write_wsl_conf(content + "\n[boot]\n" + cmd_line + "\n")
        run(["sudo", "bash", "-c", "echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register"], check=False)

    def fix_wsl_interop_persistence_down() -> None:
        if not Path("/etc/wsl.conf").is_file():
            return
        lines = read_wsl_conf().splitlines()
        kept = [line for line in lines if "WSLInterop:M::MZ::/init" not in line]
        write_wsl_conf("\n".join(kept) + "\n")

    def fix_wsl_interop_persistence_check() -> bool:
        return "WSLInterop:M::MZ::/init" in read_wsl_conf()

    return [
        Migration("install_wsl_fonts", "wsl", install_wsl_fonts_up, install_wsl_fonts_down, install_wsl_fonts_check),
        Migration("install_win32yank", "wsl", install_win32yank_up, install_win32yank_down, install_win32yank_check),
        Migration("fix_wsl_interop_persistence", "wsl", fix_wsl_interop_persistence_up, fix_wsl_interop_persistence_down, fix_wsl_interop_persistence_check),
    ]
