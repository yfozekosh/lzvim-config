"""AI feature migrations."""

from __future__ import annotations

import json
from pathlib import Path

from ..common import cmd_exists, dnf_install, run
from ..models import Migration, SetupContext


def build(ctx: SetupContext) -> list[Migration]:
    distro = ctx.distro
    repo = ctx.repo
    home = ctx.home

    def install_copilot_cli_up() -> None:
        if cmd_exists("copilot"):
            print("copilot already installed (external) - recording migration")
            return
        run(["sudo", "npm", "install", "-g", "@github/copilot"])

    def install_copilot_cli_down() -> None:
        run(["sudo", "npm", "uninstall", "-g", "@github/copilot"], check=False)
        if cmd_exists("copilot"):
            print("NOTE: copilot CLI remains (remove manually if desired).")

    def install_copilot_cli_check() -> bool:
        return cmd_exists("copilot")

    def configure_claude_statusline_up() -> None:
        settings = home / ".claude" / "settings.json"
        script_path = repo / "claude-scripts" / "statusline.sh"
        settings.parent.mkdir(parents=True, exist_ok=True)
        if not settings.is_file():
            settings.write_text("{}\n", encoding="utf-8")
        data = json.loads(settings.read_text(encoding="utf-8") or "{}")
        current = (data.get("statusLine") or {}).get("command")
        if current and current != str(script_path):
            target = current.split(" ")[0]
            is_stale = "/claude-scripts/statusline.sh" in target and target != str(script_path)
            if is_stale:
                data["statusLine"] = {"type": "command", "command": str(script_path)}
                settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
                print(f"Repaired stale statusLine.command -> {script_path}")
            elif Path(target).exists():
                print(f"statusLine.command already set to a valid external script ({current}) - leaving as-is")
            else:
                print(f"statusLine.command points at a missing script ({current}) - leaving as-is")
        elif not current:
            data["statusLine"] = {"type": "command", "command": str(script_path)}
            settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
            print(f"Configured Claude Code statusLine.command -> {script_path}")

    def configure_claude_statusline_down() -> None:
        settings = home / ".claude" / "settings.json"
        if not settings.is_file():
            return
        try:
            data = json.loads(settings.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            return
        current = (data.get("statusLine") or {}).get("command")
        if current and str(repo / "claude-scripts" / "statusline.sh") in current:
            data.pop("statusLine", None)
            settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def configure_claude_statusline_check() -> bool:
        settings = home / ".claude" / "settings.json"
        if not settings.is_file():
            return False
        try:
            data = json.loads(settings.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            return False
        current = (data.get("statusLine") or {}).get("command")
        return bool(current and str(repo / "claude-scripts" / "statusline.sh") in current)

    def install_copilot_usage_scraper_up() -> None:
        if install_copilot_usage_scraper_check():
            print("copilot usage scraper already installed (external) - recording migration")
            return
        scraper_dir = repo / "tmux-scripts" / "copilot-usage-scraper"
        run(["npm", "install"], cwd=scraper_dir)
        run(["npx", "playwright", "install", "chromium"], cwd=scraper_dir)
        if distro in {"debian", "ubuntu"}:
            run(["npx", "playwright", "install-deps", "chromium"], cwd=scraper_dir, check=False)
        elif distro == "fedora":
            dnf_install(["nss", "nspr", "atk", "cups-libs", "libdrm", "libxkbcommon", "at-spi2-atk", "libXcomposite", "libXdamage", "libXfixes", "libXrandr", "mesa-libgbm", "alsa-lib", "pango", "cairo", "libxshmfence"])
        else:
            print(f"WARNING: unsupported distro for Playwright deps: {distro}")

    def install_copilot_usage_scraper_down() -> None:
        scraper_dir = repo / "tmux-scripts" / "copilot-usage-scraper"
        import shutil
        shutil.rmtree(scraper_dir / "node_modules", ignore_errors=True)

    def install_copilot_usage_scraper_check() -> bool:
        return (repo / "tmux-scripts" / "copilot-usage-scraper" / "node_modules").is_dir()

    return [
        Migration("install_copilot_cli", "ai", install_copilot_cli_up, install_copilot_cli_down, install_copilot_cli_check),
        Migration("configure_claude_statusline", "ai", configure_claude_statusline_up, configure_claude_statusline_down, configure_claude_statusline_check),
        Migration("install_copilot_usage_scraper", "ai", install_copilot_usage_scraper_up, install_copilot_usage_scraper_down, install_copilot_usage_scraper_check),
    ]
