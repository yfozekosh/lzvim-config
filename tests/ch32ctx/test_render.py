from __future__ import annotations

import unittest

from ch32ctx.model import (
    Instruction,
    MacroDefinition,
    MacroInvocation,
    Register,
    SourceLine,
    SourceView,
    StackEntry,
)
from ch32ctx.render import ContextRenderer
from ch32ctx.theme import Theme


class FakeTarget:
    def __init__(
        self, pc: int | None = 0x3A, source_text: str = "ENABLE_SYSTICK"
    ) -> None:
        self.pc = pc
        self.source_text = source_text
        self.invalidated = False

    def invalidate(self) -> None:
        self.invalidated = True

    def current_pc(self) -> int | None:
        return self.pc

    def registers(self) -> list[Register]:
        return [Register("$sp", 0x20000800), Register("$a0", 0x2A)]

    def stack_pointer(self) -> int | None:
        return 0x20000800

    def stack(self, sp: int, count: int = 8) -> list[StackEntry]:
        return [StackEntry(sp - 4, 0x1C, 0x74)]

    def instructions(
        self, pc: int, previous: int = 4, following: int = 6
    ) -> list[Instruction]:
        return [
            Instruction(pc - 2, "li t2,-9", 2, "937203f7"),
            Instruction(pc, "and t1,t1,t2", 4, "33a3e2b3", is_current=True),
        ]

    def source_view(
        self, pc: int, before: int = 5, after: int = 5
    ) -> SourceView | None:
        return SourceView(
            "src/boot.s",
            60,
            (SourceLine(60, self.source_text, is_current=True),),
            current_text=self.source_text,
        )


class FakeMacroIndex:
    def lookup(
        self, source_path: str, line: int, line_text: str
    ) -> MacroInvocation | None:
        if line_text != "SET_CLOCK_8Mhz":
            return None
        definition = MacroDefinition(
            "SET_CLOCK_8Mhz",
            "",
            "src/rcc.s",
            32,
            (SourceLine(32, ".macro SET_CLOCK_8Mhz"),),
        )
        return MacroInvocation("SET_CLOCK_8Mhz", "", source_path, line, definition)


class RenderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.target = FakeTarget()
        self.renderer = ContextRenderer(self.target, Theme(enabled=False), width=60)

    def test_all_panes_are_rendered_in_gef_order(self) -> None:
        text = self.renderer.render()
        self.assertTrue(text.startswith("\u2500" * 50 + " registers"))
        self.assertLess(text.index("registers"), text.index("stack"))
        self.assertLess(text.index("stack"), text.index("code:riscv:rv32"))
        self.assertLess(
            text.index("code:riscv:rv32"), text.index("source:src/boot.s+60")
        )
        self.assertIn("=> 0x0000003a: 33a3e2b3 and t1,t1,t2", text)
        self.assertIn("=> 60  ENABLE_SYSTICK", text)

    def test_macro_pane_sits_between_code_and_source(self) -> None:
        target = FakeTarget(source_text="SET_CLOCK_8Mhz")
        renderer = ContextRenderer(
            target, Theme(enabled=False), width=60, macro_index=FakeMacroIndex()
        )
        text = renderer.render()
        self.assertLess(
            text.index("code:riscv:rv32"), text.index("macro:SET_CLOCK_8Mhz")
        )
        self.assertLess(
            text.index("macro:SET_CLOCK_8Mhz"), text.index("source:src/boot.s+60")
        )
        self.assertIn("executing at src/boot.s:60", text)
        self.assertIn(".macro SET_CLOCK_8Mhz", text)

    def test_macro_pane_is_omitted_when_the_line_is_not_a_macro(self) -> None:
        text = self.renderer.render()
        self.assertNotIn("macro:", text)

    def test_pane_selection_is_honoured(self) -> None:
        text = self.renderer.render(["code"])
        self.assertIn("code:riscv:rv32", text)
        self.assertNotIn("registers", text)
        self.assertNotIn("source:", text)

    def test_no_target_produces_no_output(self) -> None:
        self.target.pc = None
        self.assertEqual(self.renderer.render(), "")

    def test_render_invalidates_target_caches(self) -> None:
        self.renderer.render()
        self.assertTrue(self.target.invalidated)


if __name__ == "__main__":
    unittest.main()
