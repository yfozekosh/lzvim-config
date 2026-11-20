"""Load the shared feature manifest used by Python and Neovim."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path(__file__).resolve().parent.parent / "features.json"


def _load() -> dict[str, Any]:
    with MANIFEST_PATH.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{MANIFEST_PATH}: expected a JSON object")
    return data


_DATA = _load()

KINDS: tuple[str, ...] = tuple(_DATA.get("kinds", ()))
FEATURES: dict[str, dict[str, Any]] = dict(_DATA["features"])
PROFILES: dict[str, tuple[str, ...]] = {
    name: tuple(items) for name, items in _DATA["profiles"].items()
}
ALIASES: dict[str, tuple[str, ...]] = {
    name: tuple(items) for name, items in _DATA.get("aliases", {}).items()
}
LEGACY_CORE_IMPLIES: tuple[str, ...] = tuple(_DATA.get("legacy_core_implies", ()))
