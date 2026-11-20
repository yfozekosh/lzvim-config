"""Instruction-window selection.

The RISC-V C extension makes instruction length variable, so a fixed
``pc - n * 4`` window is wrong.  The adapter disassembles a generous range and
this module picks the requested number of instructions around the program
counter.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Sequence

from .model import Instruction


def select_window(
    instructions: Sequence[Instruction],
    pc: int,
    previous: int = 4,
    following: int = 6,
) -> list[Instruction]:
    """Return up to ``previous`` instructions before *pc* and ``following`` after it.

    The instruction exactly at *pc* is always included when it was decoded.
    If the decoder did not report *pc* (for example while stepping over a
    faulting instruction), the first decoded address at or after *pc* is used
    as the anchor and no instruction is marked current.
    """

    if not instructions:
        return []

    index: int | None = None
    for position, instruction in enumerate(instructions):
        if instruction.address == pc:
            index = position
            break
    if index is None:
        for position, instruction in enumerate(instructions):
            if instruction.address >= pc:
                index = position
                break
    if index is None:
        index = len(instructions) - 1

    start = max(0, index - max(0, previous))
    end = min(len(instructions), index + max(0, following) + 1)
    window: list[Instruction] = []
    for instruction in instructions[start:end]:
        window.append(
            replace(
                instruction,
                is_current=instruction.address == pc,
                is_past=instruction.address < pc,
            )
        )
    return window
