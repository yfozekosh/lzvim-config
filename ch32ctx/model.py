"""Data produced by the GDB adapter and consumed by the formatters.

The types are small, immutable, and independent of GDB.  Keeping the boundary
explicit makes the display code deterministic and easy to test.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Section:
    """A readable address range.

    ``end`` is exclusive, matching ELF section semantics.
    """

    start: int
    end: int
    name: str = ""
    readable: bool = True
    writable: bool = False
    executable: bool = False


@dataclass(frozen=True)
class Dereference:
    """The word stored at an address, with optional context."""

    address: int
    word: int
    symbol: str | None = None
    text: str | None = None


@dataclass(frozen=True)
class Register:
    """One core register, including an optional pointed-to word."""

    name: str
    value: int
    dereference: Dereference | None = None
    symbol: str | None = None
    changed: bool = False


@dataclass(frozen=True)
class StackEntry:
    """One word from the stack window."""

    address: int
    offset: int
    value: int | None
    dereference: Dereference | None = None


@dataclass(frozen=True)
class Instruction:
    """One decoded instruction."""

    address: int
    asm: str
    length: int
    opcode: str = ""
    symbol: str | None = None
    is_current: bool = False
    is_past: bool = False


@dataclass(frozen=True)
class SourceLine:
    """A source line, already syntax-highlighted when Pygments is available."""

    number: int
    text: str
    is_current: bool = False


@dataclass(frozen=True)
class SourceView:
    """The visible slice of a source file."""

    path: str
    line: int
    lines: tuple[SourceLine, ...]
    current_text: str = ""


@dataclass(frozen=True)
class MacroDefinition:
    """An assembler ``.macro`` definition and its body."""

    name: str
    parameters: str
    path: str
    line: int
    body: tuple[SourceLine, ...]


@dataclass(frozen=True)
class MacroInvocation:
    """A macro call found on the source line selected by the program counter."""

    name: str
    arguments: str
    path: str
    line: int
    definition: MacroDefinition
