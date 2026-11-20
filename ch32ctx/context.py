"""The ``ctx`` command and its automatic stop hook."""

from __future__ import annotations

import os
import sys
import traceback
from typing import Sequence

import gdb  # type: ignore[import-not-found]

from .render import PANES, ContextRenderer
from .source import SourceReader
from .target import GdbTarget
from .theme import Theme

_ALIASES = {
    "regs": "registers",
    "disasm": "code",
    "disassembly": "code",
    "src": "source",
    "macros": "macro",
}
_DEFAULT_WIDTH = 100


def terminal_width() -> int:
    """Best-effort terminal width without assuming stdout is a TTY."""

    try:
        return max(40, os.get_terminal_size().columns)
    except OSError:
        pass
    try:
        value = gdb.parameter("width")
    except (gdb.error, TypeError):
        value = None
    if isinstance(value, int) and value > 0:
        return max(40, value)
    return _DEFAULT_WIDTH


def _parse_panes(words: Sequence[str]) -> list[str] | None:
    if not words:
        return list(PANES)
    panes: list[str] = []
    for word in words:
        name = _ALIASES.get(word, word)
        if name == "all":
            panes.extend(PANES)
            continue
        if name not in PANES:
            return None
        if name not in panes:
            panes.append(name)
    return panes or list(PANES)


class ContextCommand(gdb.Command):
    """Display the CH32V003 context view."""

    def __init__(self, controller: Controller) -> None:
        super().__init__("ctx", gdb.COMMAND_USER)
        self._controller = controller

    def invoke(self, arg: str, from_tty: bool) -> None:
        words = [word.lower() for word in arg.split()]
        if words and words[0] in {"on", "off"}:
            self._controller.set_auto(words[0] == "on")
            return
        if words and words[0] in {"deref", "mmio"}:
            if len(words) != 2 or words[1] not in {"on", "off"}:
                gdb.write("ctx: usage: ctx deref on|off | ctx mmio on|off\n")
                return
            self._controller.set_option(words[0], words[1] == "on")
            return
        if words and words[0] in {"help", "?"}:
            self._print_help()
            return

        panes = _parse_panes(words)
        if panes is None:
            gdb.write(f"ctx: unknown pane in {arg!r}\n")
            self._print_help()
            return
        text = self._controller.renderer.render(panes, terminal_width())
        if text:
            gdb.write(text + "\n")

    def _print_help(self) -> None:
        gdb.write(
            "usage: ctx [pane ...] | ctx on | ctx off\n"
            "       ctx deref on|off | ctx mmio on|off\n"
            "panes: registers stack code macro source all\n"
        )


class Controller:
    """Own the renderer and the stop-hook policy."""

    def __init__(self) -> None:
        theme = Theme(enabled=os.environ.get("NO_COLOR") is None)
        self.target = GdbTarget(SourceReader(color=theme.enabled))
        self.renderer = ContextRenderer(self.target, theme)
        self.auto = True

    def set_auto(self, enabled: bool) -> None:
        self.auto = enabled
        gdb.write("ch32ctx: automatic context {}\n".format("on" if enabled else "off"))

    def set_option(self, name: str, enabled: bool) -> None:
        if name == "deref":
            self.target.dereference_enabled = enabled
            label = "pointer dereferences"
        else:
            self.target.mmio_enabled = enabled
            label = "MMIO dereferences"
        gdb.write("ch32ctx: {} {}\n".format(label, "on" if enabled else "off"))

    def on_stop(self, _event: object) -> None:
        if not self.auto:
            return
        try:
            text = self.renderer.render(width=terminal_width())
        except Exception:  # noqa: BLE001 - a stop hook must never break GDB
            if os.environ.get("CH32CTX_DEBUG"):
                traceback.print_exc(file=sys.stderr)
            return
        if text:
            gdb.write(text + "\n")


_controller: Controller | None = None
_installed = False


def install() -> None:
    """Register ``ctx`` and the automatic stop hook once per GDB process."""

    global _controller, _installed
    if _installed:
        return
    _controller = Controller()
    ContextCommand(_controller)
    gdb.events.stop.connect(_controller.on_stop)
    _installed = True
