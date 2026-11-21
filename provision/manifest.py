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

_RAW_DETAILS = _DATA.get("details", {})
if not isinstance(_RAW_DETAILS, dict):
    raise ValueError(f"{MANIFEST_PATH}: details must be a JSON object")

_unknown_details = set(_RAW_DETAILS) - set(FEATURES)
if _unknown_details:
    raise ValueError(
        f"{MANIFEST_PATH}: details for unknown features: {', '.join(sorted(_unknown_details))}"
    )

DETAILS: dict[str, dict[str, tuple[str, ...]]] = {}
for _fid in FEATURES:
    _entry = _RAW_DETAILS.get(_fid)
    if not isinstance(_entry, dict):
        raise ValueError(f"{MANIFEST_PATH}: missing details for feature {_fid}")
    _os = _entry.get("os")
    _nvim = _entry.get("nvim")
    if not isinstance(_os, list) or not _os:
        raise ValueError(f"{MANIFEST_PATH}: feature {_fid} needs a non-empty os detail list")
    if not isinstance(_nvim, list) or not _nvim:
        raise ValueError(f"{MANIFEST_PATH}: feature {_fid} needs a non-empty nvim detail list")
    DETAILS[_fid] = {
        "os": tuple(str(item) for item in _os),
        "nvim": tuple(str(item) for item in _nvim),
    }
