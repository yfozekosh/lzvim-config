"""Migration state, feature, and profile models."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable
from .common import is_wsl
import os
import platform


@dataclass(frozen=True)
class Record:
    verb: str  # "apply" or "undo"
    name: str
    timestamp: str
    uname: str


class MigrationLog:
    """Append-only log with apply/undo state semantics."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.records: list[Record] = []
        self._load()

    def _load(self) -> None:
        if not self.path.is_file():
            self.path.touch()
            return
        for raw in self.path.read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            parts = raw.split(maxsplit=3)
            if not parts:
                continue
            if parts[0] in {"apply", "undo"}:
                verb = parts[0]
                name = parts[1] if len(parts) > 1 else ""
                rest = parts[2:] if len(parts) > 2 else []
            else:
                # Backward compatibility: old lines had no verb.
                verb = "apply"
                name = parts[0]
                rest = parts[1:]
            timestamp = rest[0] if rest else ""
            uname = rest[1] if len(rest) > 1 else ""
            self.records.append(Record(verb=verb, name=name, timestamp=timestamp, uname=uname))

    def is_applied(self, name: str) -> bool:
        last_verb: str | None = None
        for record in self.records:
            if record.name == name:
                last_verb = record.verb
        return last_verb == "apply"

    def apply(self, name: str) -> None:
        self._append("apply", name)

    def undo(self, name: str) -> None:
        self._append("undo", name)

    def _append(self, verb: str, name: str) -> None:
        timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
        uname = platform.platform()
        line = f"{verb} {name} {timestamp} '{uname}'\n"
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(line)
        self.records.append(Record(verb=verb, name=name, timestamp=timestamp, uname=uname))


@dataclass
class Migration:
    name: str
    feature: str
    up: Callable[[], None]
    down: Callable[[], None]
    check: Callable[[], bool] = lambda: False
    depends: list[str] = field(default_factory=list)
    always: bool = False

    def run_up(self, log: MigrationLog) -> None:
        self.up()
        log.apply(self.name)

    def run_down(self, log: MigrationLog) -> None:
        self.down()
        log.undo(self.name)


@dataclass(frozen=True)
class Feature:
    id: str
    description: str
    depends: tuple[str, ...] = ()
    auto: bool = False  # enabled automatically (e.g. wsl on WSL)


class Profile:
    """Named preset of features."""

    PRESETS: dict[str, tuple[str, ...]] = {
        "minimal": ("core", "shell", "tmux", "docker", "git"),
        "work": ("core", "shell", "tmux", "docker", "git", "ai"),
        "frontend": ("core", "shell", "tmux", "docker", "git", "frontend"),
        "embedded": ("core", "shell", "tmux", "docker", "git", "build", "embedded"),
        "dotnet": ("core", "shell", "tmux", "docker", "git", "dotnet"),
        "full": (
            "core",
            "build",
            "shell",
            "tmux",
            "docker",
            "git",
            "node",
            "ai",
            "frontend",
            "dotnet",
            "embedded",
        ),
    }

    def __init__(self, name: str, features: set[str]) -> None:
        self.name = name
        self.features = set(features)

    @classmethod
    def from_name(cls, name: str) -> "Profile":
        if name not in cls.PRESETS:
            raise ValueError(f"unknown profile: {name}")
        features = set(cls.PRESETS[name])
        if is_wsl():
            features.add("wsl")
        return cls(name, features)

    def has(self, feature: str) -> bool:
        return feature in self.features


@dataclass
class SetupContext:
    repo: Path
    home: Path
    distro: str
    purge: bool
    desired: set[str]
    log: MigrationLog
    profile_name: str
