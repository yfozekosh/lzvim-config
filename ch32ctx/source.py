"""Source-file loading and optional Pygments highlighting."""

from __future__ import annotations

import os
from typing import Callable, List

from .model import SourceLine, SourceView

try:  # Pygments is optional; the context view still works without it.
    from pygments import highlight as _pygments_highlight
    from pygments.formatters import Terminal256Formatter
    from pygments.lexers import CLexer, GasLexer
except ImportError:  # pragma: no cover - exercised only on bare GDB installs
    _pygments_highlight = None
    Terminal256Formatter = None  # type: ignore[assignment]
    CLexer = None  # type: ignore[assignment]
    GasLexer = None  # type: ignore[assignment]


Highlight = Callable[[str, str], List[str]]


def _lexer_for(path: str):
    if CLexer is None:
        return None
    suffix = os.path.splitext(path)[1].lower()
    if suffix in {".c", ".h", ".cc", ".cpp", ".hpp"}:
        return CLexer()
    return GasLexer()


def highlight_source(path: str, text: str) -> list[str]:
    """Return one highlighted string per source line.

    Pygments is intentionally optional: the WCH toolchain does not ship it,
    and source colours must never prevent the rest of the view from rendering.
    """

    lines = text.splitlines()
    if _pygments_highlight is None or Terminal256Formatter is None:
        return lines
    lexer = _lexer_for(path)
    if lexer is None:
        return lines
    formatter = Terminal256Formatter(style="monokai")
    rendered = _pygments_highlight(text, lexer, formatter).splitlines()
    if len(rendered) < len(lines):
        rendered.extend([""] * (len(lines) - len(rendered)))
    return rendered[: len(lines)]


def display_path(path: str) -> str:
    """Prefer a project-relative path, but never invent ``../`` noise."""

    try:
        relative = os.path.relpath(path)
    except ValueError:  # different drives on platforms that have them
        return path
    if relative.startswith(".." + os.sep) or relative == "..":
        return path
    return relative


def _plain_source(_path: str, text: str) -> list[str]:
    return text.splitlines()


class SourceReader:
    """Read source slices and cache the expensive highlighting step."""

    def __init__(
        self, highlighter: Highlight | None = None, color: bool = True
    ) -> None:
        self._highlighter: Highlight
        if highlighter is not None:
            self._highlighter = highlighter
        else:
            self._highlighter = highlight_source if color else _plain_source
        self._cache: dict[tuple[str, int, int], tuple[list[str], list[str]]] = {}

    def _read(self, path: str) -> tuple[list[str], list[str]] | None:
        try:
            stat = os.stat(path)
            key = (path, stat.st_mtime_ns, stat.st_size)
            cached = self._cache.get(key)
            if cached is not None:
                return cached
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            return None

        highlighted = self._highlighter(path, text)
        raw = text.splitlines()
        self._cache = {key: (highlighted, raw)}
        return highlighted, raw

    def read_view(
        self,
        path: str,
        line: int,
        before: int = 5,
        after: int = 5,
    ) -> SourceView | None:
        cached = self._read(path)
        if cached is None:
            return None
        lines, raw = cached
        if not lines:
            return None
        current = min(max(1, line), len(lines))
        start = max(1, current - max(0, before))
        end = min(len(lines), current + max(0, after))
        visible = [
            SourceLine(
                number=number, text=lines[number - 1], is_current=number == current
            )
            for number in range(start, end + 1)
        ]
        return SourceView(
            path=display_path(path),
            line=current,
            lines=tuple(visible),
            current_text=raw[current - 1] if current <= len(raw) else "",
        )
