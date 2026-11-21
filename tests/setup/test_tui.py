from __future__ import annotations

import io
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import curses

from provision.features import FEATURES
from provision.tui import FeatureSelector, _format_block


class FakeScreen:
    def __init__(self, keys: list[int], height: int = 24, width: int = 100) -> None:
        self.keys = iter(keys)
        self.height = height
        self.width = width
        self.rows: dict[int, str] = {}
        self.frames: list[dict[int, str]] = []

    def getmaxyx(self) -> tuple[int, int]:
        return self.height, self.width

    def clear(self) -> None:
        self.rows.clear()

    def addnstr(self, y: int, x: int, text: str, width: int, attr: int = 0) -> None:
        self.rows[y] = text[:width]

    def refresh(self) -> None:
        self.frames.append(dict(self.rows))

    def getch(self) -> int:
        return next(self.keys)


class CursesTests(unittest.TestCase):
    def test_curses_renders_details_and_scrolls(self) -> None:
        screen = FakeScreen(
            [curses.KEY_DOWN, ord(" "), curses.KEY_NPAGE, curses.KEY_END, 10]
        )
        with patch("provision.tui.curses.curs_set", lambda _: None):
            selected = FeatureSelector({"core"}).run_curses(screen)
        self.assertIn("clangd", selected)
        self.assertTrue(any("Select features" in row for row in screen.rows.values()))
        self.assertTrue(any("Up/Down move" in row for row in screen.rows.values()))

    def test_tall_block_keeps_checkbox_visible(self) -> None:
        screen = FakeScreen([curses.KEY_DOWN, 10], height=8, width=80)
        with patch("provision.tui.curses.curs_set", lambda _: None):
            FeatureSelector({"core"}).run_curses(screen)
        self.assertTrue(any("[ ] clangd" in row for row in screen.rows.values()))

    def test_page_down_scrolls_within_tall_block(self) -> None:
        screen = FakeScreen([curses.KEY_DOWN, curses.KEY_NPAGE, 10], height=8, width=80)
        with patch("provision.tui.curses.curs_set", lambda _: None):
            FeatureSelector({"core"}).run_curses(screen)
        self.assertNotIn("[ ] clangd", screen.rows[1])
        headers = [frame[0] for frame in screen.frames]
        self.assertNotEqual(headers[-1], headers[-2])


class DetailBlockTests(unittest.TestCase):
    def test_every_feature_block_has_both_sections(self) -> None:
        for fid in FEATURES:
            block = "\n".join(_format_block(fid, 1, set(), 80))
            self.assertIn("OS:", block, fid)
            self.assertIn("Neovim:", block, fid)

    def test_group_header_and_trailing_space(self) -> None:
        block = _format_block("core", 1, set(), 80, group_header=True)
        self.assertEqual(block[0], "  ── BASE ──")
        self.assertEqual(block[-1], "")
        self.assertIn("core", block[1])

    def test_core_block_lists_distro_packages(self) -> None:
        block = "\n".join(_format_block("core", 1, {"core"}, 100))
        self.assertIn("Fedora:", block)
        self.assertIn("Debian/Ubuntu:", block)
        for package in ("neovim", "fastfetch", "gawk", "xz-utils"):
            self.assertIn(package, block)

    def test_detail_lines_wrap_to_width(self) -> None:
        for fid in FEATURES:
            for line in _format_block(fid, 1, set(), 80):
                self.assertLessEqual(len(line), 80, f"{fid}: {line}")

    def test_plain_output_includes_details(self) -> None:
        selector = FeatureSelector({"core"}, input_fn=lambda _: "d")
        output = io.StringIO()
        with patch("provision.tui.is_wsl", return_value=True):
            with redirect_stdout(output):
                selector.run_plain()
        rendered = output.getvalue()
        self.assertIn("OS:", rendered)
        self.assertIn("Neovim:", rendered)
        self.assertIn("── BASE ──", rendered)
        self.assertNotIn("\033[", rendered)
        self.assertIn("Playwright Chromium", rendered)
        self.assertIn("win32yank.exe", rendered)

if __name__ == "__main__":
    unittest.main()
