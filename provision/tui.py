"""Interactive feature selector."""

from __future__ import annotations

import curses
from typing import Callable

from .common import is_wsl
from .features import FEATURES, KIND_ORDER, can_disable, dependency_closure

_KIND_RANK = {kind: index for index, kind in enumerate(KIND_ORDER)}


def _sort_key(fid: str) -> tuple[int, str]:
    kind = FEATURES[fid].kind
    return (_KIND_RANK.get(kind, len(_KIND_RANK)), fid)


class FeatureSelector:
    """Toggle features interactively, respecting dependencies."""

    def __init__(self, selected: set[str], input_fn: Callable[[str], str] | None = None) -> None:
        self.selected = set(selected)
        self.input_fn = input_fn or input

    def _available_ids(self) -> list[str]:
        return sorted(
            (
                fid
                for fid in FEATURES
                if not FEATURES[fid].auto or is_wsl()
            ),
            key=_sort_key,
        )

    def _toggle(self, fid: str) -> None:
        if fid in self.selected:
            if can_disable(fid, self.selected):
                self.selected.discard(fid)
            else:
                print(f"cannot disable {fid}: a dependent is enabled")
        else:
            self.selected.add(fid)
            self.selected = dependency_closure(self.selected)

    def run_plain(self) -> set[str]:
        """Numbered prompt fallback (no curses)."""
        ids = self._available_ids()
        while True:
            print("\nSelect features (toggle by number, 'd' done):")
            for index, fid in enumerate(ids, start=1):
                feature = FEATURES[fid]
                mark = "x" if fid in self.selected else " "
                print(f"  {index:2}) [{mark}] {feature.kind:9} {fid:16} {feature.description}")
            raw = self.input_fn("choice> ").strip().lower()
            if raw in {"d", "done", "q"}:
                break
            if raw.isdigit():
                idx = int(raw) - 1
                if 0 <= idx < len(ids):
                    self._toggle(ids[idx])
        return set(self.selected)

    def run_curses(self, stdscr: "curses._CursesWindow") -> set[str]:  # type: ignore[attr-defined]
        curses.curs_set(0)
        ids = self._available_ids()
        pos = 0
        while True:
            stdscr.clear()
            stdscr.addstr(0, 0, "Select features (Up/Down, Space toggle, Enter done)")
            for index, fid in enumerate(ids):
                feature = FEATURES[fid]
                mark = "x" if fid in self.selected else " "
                line = f"  [{mark}] {feature.kind:9} {fid:16} {feature.description}"
                if index == pos:
                    stdscr.addstr(index + 2, 0, line, curses.A_REVERSE)
                else:
                    stdscr.addstr(index + 2, 0, line)
            stdscr.refresh()
            key = stdscr.getch()
            if key in (curses.KEY_UP, ord("k")):
                pos = (pos - 1) % len(ids)
            elif key in (curses.KEY_DOWN, ord("j")):
                pos = (pos + 1) % len(ids)
            elif key == ord(" ") or ord("1") <= key <= ord("9"):
                if key == ord(" "):
                    index = pos
                else:
                    index = key - ord("1")
                if 0 <= index < len(ids):
                    self._toggle(ids[index])
            elif key in (10, 13, curses.KEY_ENTER, ord("d")):
                break
            elif key == ord("q"):
                break
        return set(self.selected)

    def run(self) -> set[str]:
        try:
            return curses.wrapper(self.run_curses)
        except Exception:
            return self.run_plain()
