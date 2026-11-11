"""Tmux feature migrations."""

from __future__ import annotations

import platform
import re
import shutil
import tempfile
from pathlib import Path

from ..common import download_file, run, sha256_file
from ..models import Migration, SetupContext

TMUX_MEM_CPU_LOAD_TAG = "tmux-mem-cpu-load-v2"
TMUX_MEM_CPU_LOAD_VERSION = "3.8.3"
TMUX_MEM_CPU_LOAD_PREBUILT = {
    "x86_64": "5e75a9bfed2a863425696c9d1a58315fa8310bd6c27348a179e715abd6eff5f2",
}
TMUX_MEM_CPU_LOAD_RELEASE_URL = (
    "https://github.com/yfozekosh/lzvim-config/releases/download/"
    f"{TMUX_MEM_CPU_LOAD_TAG}/tmux-mem-cpu-load-linux-{{arch}}"
)


def binary_version(path: Path) -> str | None:
    """Return the version reported by a tmux-mem-cpu-load binary."""
    try:
        result = run([str(path), "-h"], check=False, capture=True)
    except OSError:
        return None
    output = f"{result.stdout or ''}\n{result.stderr or ''}"
    match = re.search(r"\bv?(\d+\.\d+\.\d+)\b", output)
    return match.group(1) if match else None


def build(ctx: SetupContext) -> list[Migration]:
    home = ctx.home
    repo = ctx.repo

    def install_tpm_up() -> None:
        if install_tpm_check():
            print("TPM already installed (external) - recording migration")
            return
        tpm_dir = home / ".tmux" / "plugins" / "tpm"
        if not (tpm_dir / ".git").is_dir():
            (home / ".tmux" / "plugins").mkdir(parents=True, exist_ok=True)
            if tpm_dir.exists():
                shutil.rmtree(tpm_dir)
            run(["git", "clone", "https://github.com/tmux-plugins/tpm", str(tpm_dir)])

    def install_tpm_down() -> None:
        shutil.rmtree(home / ".tmux" / "plugins" / "tpm", ignore_errors=True)

    def install_tpm_check() -> bool:
        return (home / ".tmux" / "plugins" / "tpm" / ".git").is_dir()

    def install_tmux_plugins_up() -> None:
        if install_tmux_plugins_check():
            print("tmux plugins already installed (external) - recording migration")
            return
        tpm_dir = home / ".tmux" / "plugins" / "tpm"
        installer = tpm_dir / "scripts" / "install_plugins.sh"
        if not installer.is_file():
            print("WARNING: TPM not found - skipping tmux plugin install.")
            return
        started = False
        try:
            run(["tmux", "info"], check=True)
        except Exception:
            run(["tmux", "new-session", "-d", "-s", "__tpm_setup__"])
            started = True
        run(["tmux", "set-environment", "-g", "TMUX_PLUGIN_MANAGER_PATH", str(home / ".tmux" / "plugins" / "")])
        run([str(installer)])
        if started:
            run(["tmux", "kill-session", "-t", "__tpm_setup__"], check=False)

    def install_tmux_plugins_down() -> None:
        plugins_dir = home / ".tmux" / "plugins"
        if plugins_dir.is_dir():
            for child in plugins_dir.iterdir():
                if child.name != "tpm" and child.is_dir():
                    shutil.rmtree(child, ignore_errors=True)

    def install_tmux_plugins_check() -> bool:
        plugins = home / ".tmux" / "plugins"
        return (plugins / "tmux-sensible").is_dir() and (plugins / "tmux-which-key").is_dir()

    def system_binary() -> Path:
        return Path("/usr/local/bin/tmux-mem-cpu-load")

    def user_binary() -> Path:
        return home / ".local" / "bin" / "tmux-mem-cpu-load"

    def active_binary() -> Path | None:
        found = shutil.which("tmux-mem-cpu-load")
        if found:
            return Path(found)
        for candidate in (user_binary(), system_binary()):
            if candidate.is_file():
                return candidate
        return None

    def install_tmux_mem_cpu_load_up() -> None:
        existing = active_binary()
        current = binary_version(existing) if existing else None
        if current == TMUX_MEM_CPU_LOAD_VERSION:
            print(f"tmux-mem-cpu-load v{TMUX_MEM_CPU_LOAD_VERSION} already installed")
            return
        if existing:
            print(
                f"Updating tmux-mem-cpu-load {current or 'unknown'} "
                f"-> v{TMUX_MEM_CPU_LOAD_VERSION}"
            )
        else:
            print(f"Installing tmux-mem-cpu-load v{TMUX_MEM_CPU_LOAD_VERSION}")
        destination = user_binary()
        destination.parent.mkdir(parents=True, exist_ok=True)
        if "build" in ctx.desired:
            install_from_source(destination)
        else:
            install_prebuilt(destination)
        installed = binary_version(destination)
        if installed != TMUX_MEM_CPU_LOAD_VERSION:
            raise RuntimeError(
                f"installed {destination} reports {installed or 'no version'}, "
                f"expected {TMUX_MEM_CPU_LOAD_VERSION}"
            )
        active = active_binary()
        if active is not None and active != destination:
            print(
                f"WARNING: tmux-mem-cpu-load still resolves to {active}; "
                f"ensure {destination.parent} precedes it in PATH"
            )

    def install_from_source(destination: Path) -> None:
        repo_dir = repo / "app-forks" / "tmux-mem-cpu-load"
        if not repo_dir.is_dir():
            raise RuntimeError(f"missing {repo_dir}")
        with tempfile.TemporaryDirectory(prefix="yf-tmux-mem-cpu-load-") as tmp:
            build_dir = Path(tmp) / "build"
            run(["cmake", "-S", str(repo_dir), "-B", str(build_dir), "-DCMAKE_BUILD_TYPE=MinSizeRel"])
            run(["cmake", "--build", str(build_dir), "--parallel", "2"])
            built = build_dir / "tmux-mem-cpu-load"
            if not built.is_file():
                raise RuntimeError(f"build did not produce {built}")
            shutil.copy2(built, destination)
        destination.chmod(0o755)

    def install_prebuilt(destination: Path) -> None:
        machine = platform.machine().lower()
        arch = {"x86_64": "x86_64", "amd64": "x86_64"}.get(machine)
        checksum = TMUX_MEM_CPU_LOAD_PREBUILT.get(arch or "")
        if arch is None or checksum is None:
            raise RuntimeError(
                f"no prebuilt tmux-mem-cpu-load for {machine}; "
                "re-run with the build feature enabled or install it manually"
            )
        asset = f"tmux-mem-cpu-load-linux-{arch}"
        local_asset = repo / "assets" / "prebuilt" / asset
        with tempfile.TemporaryDirectory(prefix="yf-tmux-mem-cpu-load-") as tmp:
            downloaded = Path(tmp) / asset
            try:
                download_file(
                    TMUX_MEM_CPU_LOAD_RELEASE_URL.format(arch=arch),
                    downloaded,
                    checksum,
                )
                shutil.copy2(downloaded, destination)
            except Exception as exc:
                print(f"WARNING: could not download {asset}: {exc}")
                if not local_asset.is_file():
                    raise RuntimeError(
                        f"no release asset and no vendored prebuilt at {local_asset}; "
                        "re-run with the build feature enabled"
                    ) from exc
                actual = sha256_file(local_asset)
                if actual != checksum:
                    raise RuntimeError(
                        f"checksum mismatch for vendored {local_asset}: "
                        f"expected {checksum}, got {actual}"
                    ) from exc
                shutil.copy2(local_asset, destination)
        destination.chmod(0o755)

    def install_tmux_mem_cpu_load_down() -> None:
        for candidate in (system_binary(), user_binary()):
            if candidate.is_file():
                try:
                    candidate.unlink()
                except PermissionError:
                    run(["sudo", "rm", "-f", str(candidate)], check=False)

    def install_tmux_mem_cpu_load_check() -> bool:
        existing = active_binary()
        return existing is not None and binary_version(existing) == TMUX_MEM_CPU_LOAD_VERSION

    return [
        Migration("install_tpm", "tmux", install_tpm_up, install_tpm_down, install_tpm_check),
        Migration("install_tmux_plugins", "tmux", install_tmux_plugins_up, install_tmux_plugins_down, install_tmux_plugins_check),
        Migration("install_tmux_mem_cpu_load", "tmux", install_tmux_mem_cpu_load_up, install_tmux_mem_cpu_load_down, install_tmux_mem_cpu_load_check),
    ]
