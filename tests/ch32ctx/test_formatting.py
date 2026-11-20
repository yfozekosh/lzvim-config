from __future__ import annotations

import unittest

from ch32ctx.formatting import (
    format_code,
    format_dereference,
    format_macro,
    format_registers,
    format_source,
    format_stack,
    title,
)
from ch32ctx.model import (
    Dereference,
    Instruction,
    MacroDefinition,
    MacroInvocation,
    Register,
    SourceLine,
    SourceView,
    StackEntry,
)
from ch32ctx.theme import Theme


class FormattingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.theme = Theme(enabled=False)

    def test_title_is_right_aligned_and_has_a_rule(self) -> None:
        self.assertEqual(
            title("registers", 20, self.theme), "\u2500" * 10 + " registers"
        )

    def test_title_falls_back_when_width_is_too_small(self) -> None:
        self.assertEqual(title("registers", 3, self.theme), "registers")

    def test_register_values_are_hex_and_unsigned_decimal(self) -> None:
        lines = format_registers(
            [
                Register("$zero", 0, Dereference(0, 0x02A0006F)),
                Register("$sp", 0x20000800),
            ],
            self.theme,
        )
        self.assertEqual(
            lines,
            [
                "$zero: 0x00000000 (         0)  \u2192 0x02a0006f",
                "$sp  : 0x20000800 ( 536872960)",
            ],
        )

    def test_register_columns_and_flash_labels_are_aligned(self) -> None:
        lines = format_registers(
            [
                Register(
                    "$ra", 0x3A, symbol="_start+16", dereference=Dereference(0, 1)
                ),
                Register("$a0", 0x2A, symbol="_start", dereference=Dereference(0, 2)),
            ],
            self.theme,
        )
        arrow_columns = [line.index("\u2192") for line in lines]
        self.assertEqual(arrow_columns[0], arrow_columns[1])
        self.assertIn("<_start+16>", lines[0])
        self.assertIn("<_start>", lines[1])

    def test_dereference_can_include_symbol_and_string(self) -> None:
        rendered = format_dereference(
            Dereference(0x20000000, 0x0000002A, symbol="_start", text='he"llo'),
            self.theme,
        )
        self.assertEqual(rendered, '\u2192 0x0000002a <_start> "he\\"llo"')

    def test_stack_uses_the_window_start_for_offsets(self) -> None:
        lines = format_stack(
            [
                StackEntry(0x200007FC, 0x1C, 0x74),
                StackEntry(0x200007F8, 0x18, None),
            ],
            self.theme,
        )
        self.assertEqual(lines[0], "0x200007fc\u2502+0x001c: 0x00000074")
        self.assertIn("??", lines[1])

    def test_code_marks_the_current_instruction_and_pads_opcodes(self) -> None:
        lines = format_code(
            [
                Instruction(0x7E, "li t2,-9", 2, "937203f7"),
                Instruction(0x80, "and t1,t1,t2", 4, "33a3e2b3", is_current=True),
            ],
            self.theme,
        )
        self.assertEqual(lines[0], "   0x0000007e: 937203f7 li t2,-9")
        self.assertEqual(lines[1], "=> 0x00000080: 33a3e2b3 and t1,t1,t2")

    def test_source_marks_the_current_line(self) -> None:
        lines = format_source(
            SourceView(
                "src/boot.s",
                3,
                (
                    SourceLine(2, "  la sp, _stack_top"),
                    SourceLine(3, "  li t0, 1", is_current=True),
                ),
            ),
            self.theme,
        )
        self.assertEqual(lines[0], "    2    la sp, _stack_top")
        self.assertEqual(lines[1], "=>  3    li t0, 1")

    def test_macro_definition_includes_origin_and_body(self) -> None:
        definition = MacroDefinition(
            "SET_CLOCK_8Mhz",
            "",
            "src/rcc.s",
            32,
            (
                SourceLine(32, ".macro SET_CLOCK_8Mhz"),
                SourceLine(33, "\tli t0, 1"),
                SourceLine(34, ".endm"),
            ),
        )
        invocation = MacroInvocation("SET_CLOCK_8Mhz", "", "src/boot.s", 60, definition)
        lines = format_macro(invocation, self.theme, limit=2)
        self.assertEqual(lines[0], "  executing at src/boot.s:60")
        self.assertEqual(lines[1], "  defined at src/rcc.s:32")
        self.assertEqual(lines[2], "  32  .macro SET_CLOCK_8Mhz")
        self.assertEqual(lines[3], "  33      li t0, 1")
        self.assertEqual(lines[4], "  ... 1 more lines")

    def test_macro_arguments_and_parameters_are_shown(self) -> None:
        definition = MacroDefinition(
            "delay_cycles",
            "cycles",
            "src/delay_cycles.s",
            1,
            (SourceLine(1, ".macro delay_cycles, cycles"),),
        )
        invocation = MacroInvocation("delay_cycles", "8", "src/boot.s", 70, definition)
        lines = format_macro(invocation, self.theme)
        self.assertIn("arguments: 8", lines[0])
        self.assertIn("parameters: cycles", lines[1])

    def test_colours_are_opt_in(self) -> None:
        plain = format_registers([Register("$a0", 1)], Theme(enabled=False))[0]
        coloured = format_registers([Register("$a0", 1)], Theme(enabled=True))[0]
        self.assertNotIn("\x1b[", plain)
        self.assertIn("\x1b[", coloured)
        self.assertIn("\x1b[0m", coloured)

    def test_changed_registers_use_bold_colour(self) -> None:
        coloured = format_registers(
            [Register("$a0", 1, changed=True)], Theme(enabled=True)
        )[0]
        self.assertIn("\x1b[1m\x1b[33m", coloured)


if __name__ == "__main__":
    unittest.main()
