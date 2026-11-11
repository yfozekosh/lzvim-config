"""Feature registry, dependency resolution, and selection persistence."""

from __future__ import annotations

from pathlib import Path

from .common import is_wsl
from .models import Feature, Profile


FEATURES: dict[str, Feature] = {
    "core": Feature("core", "Base packages (gcc, tmux, git, nvim), lazygit, symlinks"),
    "build": Feature("build", "C++ toolchain, CMake, make", ("core",)),
    "shell": Feature("shell", "bash profile, ble.sh"),
    "tmux": Feature("tmux", "TPM, tmux plugins, mem-cpu-load"),
    "docker": Feature("docker", "Docker container count in tmux status bar", ("tmux",)),
    "git": Feature("git", "GitHub CLI"),
    "node": Feature("node", "Node.js + npm", ("core",)),
    "ai": Feature("ai", "Copilot CLI, Claude statusline, usage scraper", ("core", "node")),
    "frontend": Feature("frontend", "TypeScript, Angular, Prettier", ("core", "node")),
    "dotnet": Feature("dotnet", ".NET SDK", ("core",)),
    "embedded": Feature("embedded", "RISC-V asm tools, clangd", ("core",)),
    "wsl": Feature("wsl", "WSL fonts, win32yank, interop fix", ("core",), auto=True),
}


def all_feature_ids() -> list[str]:
    return list(FEATURES.keys())


def auto_features() -> set[str]:
    result: set[str] = set()
    if is_wsl():
        result.add("wsl")
    return result


def normalize_selection(features: set[str]) -> set[str]:
    """Apply mandatory core, WSL auto-detection, and dependency closure."""
    result = set(features)
    result.add("core")
    if is_wsl():
        result.add("wsl")
    else:
        result.discard("wsl")
    return dependency_closure(result)


def dependency_closure(selected: set[str]) -> set[str]:
    """Add transitive dependencies."""
    result = set(selected)
    changed = True
    while changed:
        changed = False
        for fid in list(result):
            for dep in FEATURES[fid].depends:
                if dep not in result:
                    result.add(dep)
                    changed = True
    return result


def can_disable(feature_id: str, selected: set[str]) -> bool:
    """A feature can be disabled only if no selected feature depends on it."""
    if feature_id == "core":
        return False
    for fid in selected:
        if feature_id in FEATURES[fid].depends:
            return False
    return True


def resolve_profile(name: str) -> set[str]:
    profile = Profile.from_name(name)
    features = set(profile.features)
    features |= auto_features()
    return dependency_closure(features)


def load_selection(path: Path, default_profile: str = "full") -> tuple[str, set[str]]:
    """Load persisted selection. Falls back to profile default."""
    if not path.is_file():
        features = resolve_profile(default_profile)
        return default_profile, features
    profile_name = default_profile
    overrides: dict[str, bool] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        if raw.startswith("profile="):
            profile_name = raw.split("=", 1)[1].strip()
            continue
        if "=" in raw:
            key, value = raw.split("=", 1)
            overrides[key.strip()] = value.strip().lower() in {"1", "true", "on", "yes"}
    if profile_name == "custom":
        # Interactive selections store every feature explicitly. Features
        # added in a newer version stay off until the user opts in, instead of
        # silently inheriting whatever the current "full" preset contains.
        features = set()
    else:
        try:
            features = resolve_profile(profile_name)
        except ValueError:
            profile_name = default_profile
            features = resolve_profile(default_profile)
    for fid, enabled in overrides.items():
        if fid in FEATURES:
            if enabled:
                features.add(fid)
            else:
                features.discard(fid)
    features.add("core")
    features |= auto_features()
    if not is_wsl():
        features.discard("wsl")
    features = dependency_closure(features)
    return profile_name, features


def save_selection(path: Path, profile_name: str, features: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"profile={profile_name}"]
    for fid in sorted(FEATURES):
        lines.append(f"{fid}={'on' if fid in features else 'off'}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
