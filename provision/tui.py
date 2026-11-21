"""Interactive feature selector."""

from __future__ import annotations

import bisect
import curses
import shutil
import textwrap
from typing import Callable

from .common import is_wsl
from .features import FEATURES, KIND_ORDER, can_disable, dependency_closure

_KIND_RANK = {kind: index for index, kind in enumerate(KIND_ORDER)}


def _sort_key(fid: str) -> tuple[int, str]:
    kind = FEATURES[fid].kind
    return (_KIND_RANK.get(kind, len(_KIND_RANK)), fid)


def _wrap(text: str, width: int) -> list[str]:
    return textwrap.wrap(
        text,
        width=max(20, width),
        break_long_words=False,
        break_on_hyphens=False,
    ) or [""]


def _format_block(fid: str, index: int, selected: set[str], width: int = 100) -> list[str]:
    """Return the checkbox line and its OS/Nvim details, wrapped to width."""
    feature = FEATURES[fid]
    mark = "x" if fid in selected else " "
    heading = f"  {index:2}) [{mark}] {feature.kind:9} {fid:16} "
    description = _wrap(feature.description, width - len(heading))
    lines = [heading + description[0]]
    lines.extend(" " * len(heading) + part for part in description[1:])

    for label, entries in (
        ("OS", feature.os_details),
        ("Nvim", feature.nvim_details),
    ):
        lines.append(f"      {label}:")
        for entry in entries:
            prefix = "        - "
            wrapped = _wrap(entry, width - len(prefix))
            lines.append(prefix + wrapped[0])
            lines.extend(" " * len(prefix) + part for part in wrapped[1:])
    return lines


def _block_at(starts: list[int], line: int) -> int:
    if not starts:
        return 0
    return max(0, min(bisect.bisect_right(starts, line) - 1, len(starts) - 1))


def _addstr(
    stdscr: "curses._CursesWindow",  # type: ignore[attr-defined]
    y: int,
    x: int,
    text: str,
    width: int,
    attr: int = 0,
) -> None:
    if width <= 0:
        return
    try:
        stdscr.addnstr(y, x, text, width, attr)
    except curses.error:
        pass


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
        width = max(40, min(shutil.get_terminal_size((100, 24)).columns, 120))
        while True:
            print("\nSelect features (toggle by number, 'd' done):")
            for index, fid in enumerate(ids, start=1):
                for line in _format_block(fid, index, self.selected, width):
                    print(line)
                print()
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
        top = 0
        ensure_visible = True

        while True:
            max_y, max_x = stdscr.getmaxyx()
            width = max(20, max_x)
            blocks = [
                _format_block(fid, index, self.selected, width)
                for index, fid in enumerate(ids, start=1)
            ]
            starts: list[int] = []
            total = 0
            for block in blocks:
                starts.append(total)
                total += len(block)

            view_h = max(1, max_y - 2)
            max_top = max(0, total - view_h)
            top = max(0, min(top, max_top))

            if starts and blocks:
                start = starts[pos]
                end = start + len(blocks[pos])
                if ensure_visible:
                    if start < top:
                        top = start
                    elif end > top + view_h:
                        if end - start <= view_h:
                            top = min(max_top, end - view_h)
                        else:
                            # A block taller than the viewport keeps its checkbox
                            # visible until PgUp/PgDn scrolls through it.
                            top = start
            ensure_visible = False

            stdscr.clear()
            _addstr(
                stdscr,
                0,
                0,
                f"Select features  [{pos + 1}/{len(ids)}]  "
                f"lines {top + 1}-{min(total, top + view_h)}/{total}",
                max_x,
                curses.A_BOLD,
            )

            for index, block in enumerate(blocks):
                block_start = starts[index]
                for offset, line in enumerate(block):
                    screen_y = 1 + block_start + offset - top
                    if 1 <= screen_y < max_y - 1:
                        attr = curses.A_REVERSE if index == pos and offset == 0 else 0
                        _addstr(stdscr, screen_y, 0, line, max_x, attr)

            _addstr(
                stdscr,
                max_y - 1,
                0,
                "Up/Down move  PgUp/PgDn scroll  Space/1-9 toggle  Enter/d/q done",
                max_x - 1,
                curses.A_DIM,
            )
            stdscr.refresh()

            key = stdscr.getch()
            if key in (curses.KEY_UP, ord("k")):
                pos = (pos - 1) % len(ids)
                ensure_visible = True
            elif key in (curses.KEY_DOWN, ord("j")):
                pos = (pos + 1) % len(ids)
                ensure_visible = True
            elif key == curses.KEY_PPAGE:
                top = max(0, top - view_h)
                pos = _block_at(starts, min(top, max(0, total - 1)))
            elif key == curses.KEY_NPAGE:
                top = min(max_top, top + view_h)
                pos = _block_at(starts, min(top, max(0, total - 1)))
            elif key in (curses.KEY_HOME, ord("g")):
                pos = 0
                top = 0
                ensure_visible = True
            elif key in (curses.KEY_END, ord("G")):
                pos = len(ids) - 1
                top = max_top
                ensure_visible = True
            elif key == curses.KEY_RESIZE:
                ensure_visible = True
                continue
            elif key == ord(" ") or ord("1") <= key <= ord("9"):
                index = pos if key == ord(" ") else key - ord("1")
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
