"""Feature registry, dependency resolution, and selection persistence."""

from __future__ import annotations

from pathlib import Path

from .common import is_wsl
from .manifest import (
    ALIASES,
    DETAILS,
    FEATURES as FEATURE_DATA,
    KINDS,
    LEGACY_CORE_IMPLIES,
)
from .models import Feature, Profile


FEATURES: dict[str, Feature] = {
    fid: Feature(
        id=fid,
        description=data["description"],
        depends=tuple(data.get("depends", ())),
        auto=bool(data.get("auto", False)),
        kind=data.get("kind", "tool"),
        os_details=DETAILS[fid]["os"],
        nvim_details=DETAILS[fid]["nvim"],
    )
    for fid, data in FEATURE_DATA.items()
}
KIND_ORDER: tuple[str, ...] = KINDS


def all_feature_ids() -> list[str]:
    return list(FEATURES.keys())


def auto_features() -> set[str]:
    """Features enabled automatically for the current platform."""
    if not is_wsl():
        return set()
    return {fid for fid, feature in FEATURES.items() if feature.auto}


def expand_aliases(features: set[str]) -> set[str]:
    """Expand legacy feature names (ai, embedded, wsl) to their components."""
    result: set[str] = set()
    for fid in features:
        result.update(ALIASES.get(fid, (fid,)))
    return result


def normalize_selection(features: set[str]) -> set[str]:
    """Apply mandatory core, drop inapplicable platform features, close deps.

    Auto features are not added here: they are defaults applied by profile
    resolution/loading, so an explicit interactive opt-out survives.
    """
    result = expand_aliases(set(features))
    applicable = auto_features()
    result = {
        fid
        for fid in result
        if fid in FEATURES and (FEATURES[fid].auto is False or fid in applicable)
    }
    result.add("core")
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
    features = expand_aliases(set(profile.features))
    features |= auto_features()
    return dependency_closure(features)


def _canonical_overrides(raw: dict[str, bool]) -> dict[str, bool]:
    """Expand aliases while preserving file order (last entry wins)."""
    result: dict[str, bool] = {}
    for key, enabled in raw.items():
        if key in FEATURES:
            result[key] = enabled
        elif key in ALIASES:
            for fid in ALIASES[key]:
                result[fid] = enabled
    return result


def load_selection(path: Path, default_profile: str = "full") -> tuple[str, set[str]]:
    """Load persisted selection. Falls back to profile default."""
    if not path.is_file():
        features = resolve_profile(default_profile)
        return default_profile, features
    profile_name = default_profile
    raw_overrides: dict[str, bool] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        if raw.startswith("profile="):
            profile_name = raw.split("=", 1)[1].strip()
            continue
        if "=" in raw:
            key, value = raw.split("=", 1)
            raw_overrides[key.strip()] = value.strip().lower() in {"1", "true", "on", "yes"}
    overrides = _canonical_overrides(raw_overrides)
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
        if enabled:
            features.add(fid)
        else:
            features.discard(fid)

    if profile_name == "custom":
        # Before the nvim split, bootstrap/prune lived in core. Keep existing
        # custom selections working unless they explicitly disabled nvim.
        if overrides.get("core") and "nvim" not in overrides:
            features.update(LEGACY_CORE_IMPLIES)
        # Platform features are environment defaults; an explicit off entry
        # (written by the interactive selector) wins.
        for fid in auto_features():
            if overrides.get(fid) is not False:
                features.add(fid)

    features.add("core")
    return profile_name, normalize_selection(features)


def save_selection(path: Path, profile_name: str, features: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"profile={profile_name}"]
    for fid in sorted(FEATURES):
        lines.append(f"{fid}={'on' if fid in features else 'off'}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
