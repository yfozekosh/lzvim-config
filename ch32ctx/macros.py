"""Find assembler macro definitions and the macro called at a source line.

GDB maps every instruction produced by a macro expansion back to the line that
invoked the macro.  The disassembly is therefore correct, but the source pane
cannot show the macro body.  This module indexes ``.macro`` blocks in the
project's assembler sources and resolves the invocation visible at ``$pc``.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable

from .model import MacroDefinition, MacroInvocation, SourceLine
from .source import display_path

_MACRO_RE = re.compile(
    r"^\s*\.macro\s+([A-Za-z_.$][\w.$]*)(?:\s*,?\s*(.*))?$",
    re.IGNORECASE,
)
_ENDM_RE = re.compile(r"^\s*\.endm\b", re.IGNORECASE)
_LABEL_RE = re.compile(r"^[A-Za-z_.$][\w.$]*:\s*")
_INVOCATION_RE = re.compile(r"^([A-Za-z_.$][\w.$]*)")
_SOURCE_SUFFIXES = {".s", ".inc"}


def parse_invocation(text: str) -> tuple[str, str] | None:
    """Return ``(name, arguments)`` for a line that may call a macro.

    Labels and comments are stripped.  Directives and empty lines return
    ``None``; instruction names are returned and simply fail to match a macro
    definition later.
    """

    text = text.split("#", 1)[0].split("//", 1)[0].strip()
    if not text or text.startswith("."):
        return None
    text = _LABEL_RE.sub("", text, count=1)
    match = _INVOCATION_RE.match(text)
    if match is None:
        return None
    name = match.group(1)
    arguments = text[match.end() :].strip()
    if arguments.startswith("(") and arguments.endswith(")"):
        arguments = arguments[1:-1].strip()
    return name, arguments


class MacroIndex:
    """Index macro definitions in the source tree that owns ``source_path``.

    Only the last index is cached.  The cache key includes the size and mtime
    of every candidate file, so editing a macro is visible on the next stop
    without restarting GDB.
    """

    def __init__(self, source_paths: Iterable[str] | None = None) -> None:
        self._source_paths = tuple(source_paths) if source_paths is not None else None
        self._cache_key: tuple[str, tuple[tuple[str, int, int], ...]] | None = None
        self._cache: dict[str, MacroDefinition] = {}

    def lookup(
        self, source_path: str, line: int, line_text: str
    ) -> MacroInvocation | None:
        """Resolve the macro call on ``line_text`` at ``line``."""

        parsed = parse_invocation(line_text)
        if parsed is None:
            return None
        name, arguments = parsed
        definition = self._definitions(source_path).get(name)
        if definition is None:
            return None
        return MacroInvocation(
            name=name,
            arguments=arguments,
            path=display_path(source_path),
            line=line,
            definition=definition,
        )

    def _definitions(self, source_path: str) -> dict[str, MacroDefinition]:
        paths = self._paths(source_path)
        signature = self._signature(paths)
        key = (str(Path(source_path).expanduser().resolve().parent), signature)
        if key == self._cache_key:
            return self._cache

        definitions: dict[str, MacroDefinition] = {}
        for path in paths:
            definitions.update(self._parse_file(path))
        self._cache_key = key
        self._cache = definitions
        return definitions

    def _paths(self, source_path: str) -> tuple[Path, ...]:
        if self._source_paths is not None:
            return tuple(Path(path).expanduser() for path in self._source_paths)

        resolved = Path(source_path).expanduser()
        if not resolved.is_absolute():
            resolved = (Path.cwd() / resolved).resolve()
        root = resolved.parent
        for parent in (resolved.parent, *resolved.parents):
            if parent.name == "src":
                root = parent
                break
        else:
            root = resolved.parent

        paths = [
            path
            for path in root.rglob("*")
            if path.is_file() and path.suffix.lower() in _SOURCE_SUFFIXES
        ]
        if resolved not in paths:
            paths.append(resolved)
        return tuple(sorted(paths))

    @staticmethod
    def _signature(paths: Iterable[Path]) -> tuple[tuple[str, int, int], ...]:
        signature = []
        for path in paths:
            try:
                stat = path.stat()
            except OSError:
                continue
            signature.append((str(path), stat.st_mtime_ns, stat.st_size))
        return tuple(signature)

    def _parse_file(self, path: Path) -> dict[str, MacroDefinition]:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return {}

        definitions: dict[str, MacroDefinition] = {}
        index = 0
        while index < len(lines):
            match = _MACRO_RE.match(lines[index])
            if match is None:
                index += 1
                continue

            name = match.group(1)
            parameters = (match.group(2) or "").strip()
            start = index
            index += 1
            while index < len(lines) and _ENDM_RE.match(lines[index]) is None:
                index += 1
            end = min(index, len(lines) - 1)
            body = tuple(
                SourceLine(number=number + 1, text=lines[number])
                for number in range(start, end + 1)
            )
            definitions[name] = MacroDefinition(
                name=name,
                parameters=parameters,
                path=display_path(str(path)),
                line=start + 1,
                body=body,
            )
            index = end + 1
        return definitions


__all__ = ["MacroIndex", "parse_invocation"]
