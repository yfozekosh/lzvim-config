from __future__ import annotations

import unittest

from ch32ctx.model import Instruction
from ch32ctx.window import select_window


def insn(address: int, length: int = 4) -> Instruction:
    return Instruction(address=address, asm="nop", length=length)


class WindowTests(unittest.TestCase):
    def test_mixed_length_window_includes_the_instruction_at_pc(self) -> None:
        instructions = [insn(0x74), insn(0x78), insn(0x7A), insn(0x7E, 2), insn(0x80)]
        window = select_window(instructions, 0x80, previous=1, following=1)
        self.assertEqual([item.address for item in window], [0x7E, 0x80])
        self.assertTrue(window[1].is_current)
        self.assertTrue(window[0].is_past)

    def test_window_is_clipped_at_the_start(self) -> None:
        instructions = [insn(0x0), insn(0x2, 2), insn(0x4)]
        window = select_window(instructions, 0x2, previous=4, following=1)
        self.assertEqual([item.address for item in window], [0x0, 0x2, 0x4])

    def test_anchor_after_pc_does_not_claim_a_current_instruction(self) -> None:
        instructions = [insn(0x10), insn(0x14)]
        window = select_window(instructions, 0x12)
        self.assertFalse(any(item.is_current for item in window))
        self.assertTrue(window[0].is_past)

    def test_empty_disassembly_is_safe(self) -> None:
        self.assertEqual(select_window([], 0x0), [])


if __name__ == "__main__":
    unittest.main()
