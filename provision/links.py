"""Feature-owned config symlinks.

Each feature manages the links for the files it owns. Selected migrations
re-run ``up`` on every setup (see ``provision.main.reconcile``), so this also
repairs links that were removed or replaced outside setup.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .common import ensure_symlink, remove_symlink_if_points_to
from .models import Migration


@dataclass(frozen=True)
class ConfigLink:
    target: Path  # file or directory in the repo
    link: Path  # location under $HOME


def _points_at(link: Path, target: Path) -> bool:
    try:
        return link.readlink() == target
    except OSError:
        return False


def link_migration(name: str, feature: str, links: list[ConfigLink]) -> Migration:
    """Build a migration that owns a feature's symlinks."""

    def up() -> None:
        for item in links:
            ensure_symlink(item.target, item.link)

    def down() -> None:
        for item in links:
            remove_symlink_if_points_to(item.link, item.target)

    def check() -> bool:
        # Any owned link counts as present so unselecting the feature removes
        # leftovers from older core-managed installs too.
        return any(_points_at(item.link, item.target) for item in links)

    return Migration(name, feature, up, down, check)
