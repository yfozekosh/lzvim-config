"""Pure text rendering for the context view.

Every function takes already-collected data.  No function in this module
touches GDB, the terminal, or the filesystem.
"""

from __future__ import annotations

from typing import Sequence

from .model import (
    Dereference,
    Instruction,
    MacroInvocation,
    Register,
    SourceView,
    StackEntry,
)
from .theme import BOLD, CYAN, DIM, GRAY, GREEN, MAGENTA, YELLOW, Theme


def title(name: str, width: int, theme: Theme) -> str:
    """Render a right-aligned pane heading with a rule on the left."""

    name = name.strip()
    if width <= len(name):
        return theme.style(name, CYAN)
    fill = max(0, width - len(name) - 1)
    if not fill:
        return theme.style(name, CYAN)
    return theme.style("\u2500" * fill + " ", DIM) + theme.style(name, CYAN)


def format_dereference(dereference: Dereference, theme: Theme) -> str:
    """Render the ``-> 0x...`` suffix used by registers and stack words."""

    parts = [
        theme.style("\u2192", GRAY),
        theme.style(f"0x{dereference.word:08x}", CYAN),
    ]
    if dereference.symbol:
        parts.append(theme.style(f"<{dereference.symbol}>", MAGENTA))
    if dereference.text:
        text = dereference.text.replace("\\", "\\\\").replace('"', '\\"')
        parts.append(theme.style(f'"{text}"', GREEN))
    return " ".join(parts)


def format_registers(registers: Sequence[Register], theme: Theme) -> list[str]:
    """Render the register pane."""

    if not registers:
        return []
    name_width = max(len(register.name) for register in registers)
    decimal_width = max(10, max(len(str(register.value)) for register in registers))
    label_width = max(
        (len(f"<{register.symbol}>") for register in registers if register.symbol),
        default=0,
    )
    lines: list[str] = []
    for register in registers:
        value_style = (BOLD, YELLOW) if register.changed else (YELLOW,)
        line = "{}: {} ({})".format(
            theme.style(register.name.ljust(name_width), CYAN),
            theme.style(f"0x{register.value:08x}", *value_style),
            theme.style(f"{register.value:>{decimal_width}}", GRAY),
        )
        label = f"<{register.symbol}>" if register.symbol else ""
        if label:
            line += " " + theme.style(label, MAGENTA)
        if register.dereference:
            if label:
                line += " " * (label_width - len(label))
            elif label_width:
                line += " " * (label_width + 1)
            line += "  " + format_dereference(register.dereference, theme)
        lines.append(line)
    return lines


def format_stack(entries: Sequence[StackEntry], theme: Theme) -> list[str]:
    """Render the stack pane, one word per line."""

    lines: list[str] = []
    for entry in entries:
        if entry.value is None:
            value = theme.style("??", YELLOW)
        else:
            value = theme.style(f"0x{entry.value:08x}", YELLOW)
        line = "{}\u2502{}: {}".format(
            theme.style(f"0x{entry.address:08x}", CYAN),
            theme.style(f"+0x{entry.offset:04x}", GRAY),
            value,
        )
        if entry.dereference:
            line += "  " + format_dereference(entry.dereference, theme)
        lines.append(line)
    return lines


def format_code(instructions: Sequence[Instruction], theme: Theme) -> list[str]:
    """Render the disassembly pane with a current-instruction marker."""

    if not instructions:
        return []
    opcode_width = max(8, max(len(instruction.opcode) for instruction in instructions))
    lines: list[str] = []
    for instruction in instructions:
        attr: tuple[str, ...]
        if instruction.is_current:
            arrow = theme.style("=>", GREEN)
            attr = (GREEN,)
        elif instruction.is_past:
            arrow = "  "
            attr = (DIM,)
        else:
            arrow = "  "
            attr = ()

        symbol = ""
        if instruction.symbol:
            symbol = " " + theme.style(f"<{instruction.symbol}>", MAGENTA)

        line = f"{arrow} 0x{instruction.address:08x}{symbol}: {theme.style(instruction.opcode.ljust(opcode_width), GRAY)} {theme.style(instruction.asm, *attr)}"
        lines.append(line)
    return lines


def format_source(view: SourceView, theme: Theme) -> list[str]:
    """Render a source slice with line numbers and a current-line marker."""

    if not view.lines:
        return []
    number_width = max(2, len(str(max(line.number for line in view.lines))))
    lines: list[str] = []
    for line in view.lines:
        arrow = theme.style("=>", GREEN) if line.is_current else "  "
        number = theme.style(
            "{:>{width}}".format(line.number, width=number_width), GRAY
        )
        lines.append(f"{arrow} {number}  {line.text}")
    return lines


def format_macro(
    invocation: MacroInvocation, theme: Theme, limit: int = 32
) -> list[str]:
    """Render the definition of the macro invoked at the current source line."""

    definition = invocation.definition
    details = f"executing at {invocation.path}:{invocation.line}"
    if invocation.arguments:
        details += f"; arguments: {invocation.arguments}"
    lines = [theme.style(f"  {details}", GRAY)]
    definition_line = f"  defined at {definition.path}:{definition.line}"
    if definition.parameters:
        definition_line += f"; parameters: {definition.parameters}"
    lines.append(theme.style(definition_line, GRAY))

    body = definition.body
    visible = body[: max(0, limit)]
    if visible:
        number_width = max(2, len(str(max(line.number for line in visible))))
        for line in visible:
            number = theme.style(
                "{:>{width}}".format(line.number, width=number_width), GRAY
            )
            text = line.text.replace("\t", "    ")
            lines.append(f"  {number}  {text}")
    hidden = len(body) - len(visible)
    if hidden > 0:
        lines.append(theme.style(f"  ... {hidden} more lines", GRAY))
    return lines
