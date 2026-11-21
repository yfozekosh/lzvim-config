"""Interactive feature selector."""

from __future__ import annotations

import bisect
import curses
import os
import shutil
import sys
import textwrap
from typing import Callable

from .common import is_wsl
from .features import FEATURES, KIND_ORDER, can_disable, dependency_closure

_KIND_RANK = {kind: index for index, kind in enumerate(KIND_ORDER)}


def _sort_key(fid: str) -> tuple[int, str]:
    kind = FEATURES[fid].kind
    return (_KIND_RANK.get(kind, len(_KIND_RANK)), fid)


def _color_enabled() -> bool:
    return (
        hasattr(sys.stdout, "isatty")
        and sys.stdout.isatty()
        and os.environ.get("NO_COLOR") is None
        and os.environ.get("TERM", "").lower() != "dumb"
    )


def _paint(text: str, code: str, enabled: bool) -> str:
    if not enabled:
        return text
    return f"\033[{code}m{text}\033[0m"


def _plain_line(line: str, enabled: bool) -> str:
    stripped = line.strip()
    if stripped.startswith("── "):
        return _paint(line, "1;36", enabled)
    if ") [x] " in line:
        return _paint(line, "1;32", enabled)
    if stripped.startswith("OS:"):
        return _paint(line, "1;33", enabled)
    if stripped.startswith("Neovim:"):
        return _paint(line, "1;35", enabled)
    if stripped.startswith("- "):
        split = line.index("- ") + 2
        return _paint(line[:split], "36", enabled) + line[split:]
    return line


def _curses_styles() -> dict[str, int]:
    if os.environ.get("NO_COLOR") is not None:
        return {}
    try:
        if not curses.has_colors():
            return {}
        curses.start_color()
        try:
            curses.use_default_colors()
            background = -1
        except curses.error:
            background = curses.COLOR_BLACK
        specs = {
            "title": (curses.COLOR_CYAN, background),
            "kind": (curses.COLOR_CYAN, background),
            "selected": (curses.COLOR_GREEN, background),
            "os": (curses.COLOR_YELLOW, background),
            "nvim": (curses.COLOR_MAGENTA, background),
            "detail": (curses.COLOR_CYAN, background),
        }
        styles: dict[str, int] = {}
        for index, (name, (foreground, back)) in enumerate(specs.items(), start=1):
            curses.init_pair(index, foreground, back)
            styles[name] = curses.color_pair(index)
        return styles
    except curses.error:
        return {}


def _is_heading(line: str, index: int) -> bool:
    return line.strip().startswith(f"{index}) [")


def _line_attr(line: str, styles: dict[str, int]) -> int:
    stripped = line.strip()
    if stripped.startswith("── "):
        return styles.get("kind", 0) | curses.A_BOLD
    if stripped.startswith("OS:"):
        return styles.get("os", 0) | curses.A_BOLD
    if stripped.startswith("Neovim:"):
        return styles.get("nvim", 0) | curses.A_BOLD
    if stripped.startswith("- "):
        return styles.get("detail", 0)
    return 0


def _wrap(text: str, width: int) -> list[str]:
    return textwrap.wrap(
        text,
        width=max(20, width),
        break_long_words=False,
        break_on_hyphens=False,
    ) or [""]


def _format_block(
    fid: str,
    index: int,
    selected: set[str],
    width: int = 100,
    group_header: bool = False,
) -> list[str]:
    """Return the checkbox line and its OS/Neovim details, wrapped to width."""
    feature = FEATURES[fid]
    mark = "x" if fid in selected else " "
    lines: list[str] = []
    if group_header:
        lines.append(f"  ── {feature.kind.upper()} ──")
    heading = f"  {index:2}) [{mark}] {fid:16} "
    description = _wrap(feature.description, width - len(heading))
    lines.append(heading + description[0])
    lines.extend(" " * len(heading) + part for part in description[1:])

    for label, entries in (
        ("OS", feature.os_details),
        ("Neovim", feature.nvim_details),
    ):
        lines.append(f"      {label}:")
        for entry in entries:
            prefix = "        - "
            wrapped = _wrap(entry, width - len(prefix))
            lines.append(prefix + wrapped[0])
            lines.extend(" " * len(prefix) + part for part in wrapped[1:])
    lines.append("")
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
        color = _color_enabled()
        while True:
            print()
            print(
                _paint(
                    f"Select features  selected {len(self.selected)}  "
                    "(toggle by number, 'd' done)",
                    "1;36",
                    color,
                )
            )
            previous_kind = ""
            for index, fid in enumerate(ids, start=1):
                kind = FEATURES[fid].kind
                first_in_kind = kind != previous_kind
                previous_kind = kind
                for line in _format_block(
                    fid,
                    index,
                    self.selected,
                    width,
                    group_header=first_in_kind,
                ):
                    print(_plain_line(line, color))
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
        styles = _curses_styles()
        ids = self._available_ids()
        pos = 0
        top = 0
        ensure_visible = True

        while True:
            max_y, max_x = stdscr.getmaxyx()
            width = max(20, max_x)
            blocks: list[list[str]] = []
            previous_kind = ""
            for index, fid in enumerate(ids, start=1):
                kind = FEATURES[fid].kind
                first_in_kind = kind != previous_kind
                previous_kind = kind
                blocks.append(
                    _format_block(
                        fid,
                        index,
                        self.selected,
                        width,
                        group_header=first_in_kind,
                    )
                )
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
                f"selected {len(self.selected)}  "
                f"lines {top + 1}-{min(total, top + view_h)}/{total}",
                max_x,
                curses.A_BOLD | styles.get("title", 0),
            )

            for index, block in enumerate(blocks):
                block_start = starts[index]
                checked = ids[index] in self.selected
                for offset, line in enumerate(block):
                    screen_y = 1 + block_start + offset - top
                    if 1 <= screen_y < max_y - 1:
                        attr = _line_attr(line, styles)
                        if _is_heading(line, index + 1):
                            if checked:
                                attr |= styles.get("selected", 0) | curses.A_BOLD
                            if index == pos:
                                attr |= curses.A_REVERSE
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
