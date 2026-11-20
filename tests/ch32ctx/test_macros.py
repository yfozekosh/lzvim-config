from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ch32ctx.macros import MacroIndex, parse_invocation


class ParseInvocationTests(unittest.TestCase):
    def test_plain_macro_call(self) -> None:
        self.assertEqual(parse_invocation("SET_CLOCK_8Mhz"), ("SET_CLOCK_8Mhz", ""))

    def test_comments_labels_and_arguments_are_handled(self) -> None:
        self.assertEqual(
            parse_invocation("loop: delay_cycles 12  # one second"),
            ("delay_cycles", "12"),
        )

    def test_directives_and_empty_lines_are_not_macro_calls(self) -> None:
        self.assertIsNone(parse_invocation("  .equ FLASH_ACTLR, 0x40022000"))
        self.assertIsNone(parse_invocation(""))
        self.assertEqual(parse_invocation("  li t0, 0"), ("li", "t0, 0"))


class MacroIndexTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.src = self.root / "src"
        self.src.mkdir()
        self.boot = self.src / "boot.s"
        self.clock = self.src / "clock.s"
        self.boot.write_text(
            ".section .text\nstart:\n\tSET_CLOCK_8Mhz\n\tdelay_cycles 8\n",
            encoding="utf-8",
        )
        self.clock.write_text(
            ".macro SET_CLOCK_8Mhz\n"
            "\tli t0, 0x40021000\n"
            "\tli t1, 3\n"
            ".endm\n"
            "\n"
            ".macro delay_cycles, cycles\n"
            "\tnop\n"
            ".endm\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_lookup_finds_a_definition_in_a_sibling_file(self) -> None:
        invocation = MacroIndex().lookup(str(self.boot), 3, "SET_CLOCK_8Mhz")
        self.assertIsNotNone(invocation)
        assert invocation is not None
        self.assertEqual(invocation.name, "SET_CLOCK_8Mhz")
        self.assertEqual(invocation.line, 3)
        self.assertEqual(invocation.definition.name, "SET_CLOCK_8Mhz")
        self.assertEqual(invocation.definition.line, 1)
        self.assertIn("li t0, 0x40021000", invocation.definition.body[1].text)

    def test_lookup_reports_arguments_and_definition_parameters(self) -> None:
        invocation = MacroIndex().lookup(str(self.boot), 4, "delay_cycles 8")
        self.assertIsNotNone(invocation)
        assert invocation is not None
        self.assertEqual(invocation.arguments, "8")
        self.assertEqual(invocation.definition.parameters, "cycles")

    def test_lookup_returns_none_for_inactive_or_unknown_lines(self) -> None:
        index = MacroIndex()
        self.assertIsNone(index.lookup(str(self.boot), 2, "start:"))
        self.assertIsNone(index.lookup(str(self.boot), 3, "li t0, 0"))
        self.assertIsNone(index.lookup(str(self.boot), 3, "NOT_A_MACRO"))

    def test_explicit_source_paths_support_non_standard_layouts(self) -> None:
        other = self.root / "other"
        other.mkdir()
        macro_file = other / "macros.inc"
        macro_file.write_text(".macro only_here\n\tnop\n.endm\n", encoding="utf-8")
        index = MacroIndex(source_paths=[str(macro_file)])
        invocation = index.lookup(str(self.boot), 1, "only_here")
        self.assertIsNotNone(invocation)
        assert invocation is not None
        self.assertEqual(invocation.definition.name, "only_here")


if __name__ == "__main__":
    unittest.main()
