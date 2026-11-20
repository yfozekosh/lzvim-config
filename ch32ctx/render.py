"""Assemble target data into the display panes.

The renderer depends on a small target protocol, not on GDB.  This keeps the
full layout testable with synthetic register, stack, and disassembly data.
"""

from __future__ import annotations

from typing import Protocol, Sequence

from .formatting import (
    format_code,
    format_macro,
    format_registers,
    format_source,
    format_stack,
    title,
)
from .macros import MacroIndex
from .model import Instruction, Register, SourceView, StackEntry
from .theme import Theme

PANES: tuple[str, ...] = ("registers", "stack", "code", "macro", "source")


class Target(Protocol):
    """The subset of the GDB adapter used by the renderer."""

    def invalidate(self) -> None: ...

    def current_pc(self) -> int | None: ...

    def registers(self) -> list[Register]: ...

    def stack_pointer(self) -> int | None: ...

    def stack(self, sp: int, count: int = 8) -> list[StackEntry]: ...

    def instructions(
        self, pc: int, previous: int = 4, following: int = 6
    ) -> list[Instruction]: ...

    def source_view(
        self, pc: int, before: int = 5, after: int = 5
    ) -> SourceView | None: ...


class ContextRenderer:
    """Collect target data and turn it into the display panes."""

    def __init__(
        self,
        target: Target,
        theme: Theme,
        width: int = 100,
        macro_index: MacroIndex | None = None,
    ) -> None:
        self.target = target
        self.theme = theme
        self.width = width
        self.macro_index = macro_index if macro_index is not None else MacroIndex()

    def render(self, panes: Sequence[str] = PANES, width: int | None = None) -> str:
        self.target.invalidate()
        pc = self.target.current_pc()
        if pc is None:
            return ""
        columns = max(40, width if width is not None else self.width)
        blocks: list[str] = []
        selected = set(panes)

        if "registers" in selected:
            registers = self.target.registers()
            if registers:
                blocks.append(title("registers", columns, self.theme))
                blocks.extend(format_registers(registers, self.theme))

        if "stack" in selected:
            sp = self.target.stack_pointer()
            if sp is not None:
                blocks.append(title("stack", columns, self.theme))
                blocks.extend(format_stack(self.target.stack(sp, 8), self.theme))

        if "code" in selected:
            instructions = self.target.instructions(pc)
            if instructions:
                blocks.append(title("code:riscv:rv32", columns, self.theme))
                blocks.extend(format_code(instructions, self.theme))

        source = None
        if "source" in selected or "macro" in selected:
            source = self.target.source_view(pc)

        if "macro" in selected and source is not None:
            invocation = self.macro_index.lookup(
                source.path, source.line, source.current_text
            )
            if invocation is not None:
                blocks.append(title(f"macro:{invocation.name}", columns, self.theme))
                blocks.extend(format_macro(invocation, self.theme))

        if "source" in selected and source is not None:
            blocks.append(
                title(
                    f"source:{source.path}+{source.line}",
                    columns,
                    self.theme,
                )
            )
            blocks.extend(format_source(source, self.theme))

        return "\n".join(blocks)
