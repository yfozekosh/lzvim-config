from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from ch32ctx.source import SourceReader, display_path


class SourceReaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "boot.s"
        self.path.write_text(
            "\n".join(f"line {n}" for n in range(1, 21)) + "\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_reads_the_requested_window_and_marks_the_current_line(self) -> None:
        reader = SourceReader(highlighter=lambda _path, text: text.splitlines())
        view = reader.read_view(str(self.path), 10, before=1, after=1)
        assert view is not None
        self.assertEqual([line.number for line in view.lines], [9, 10, 11])
        self.assertEqual([line.is_current for line in view.lines], [False, True, False])

    def test_clamps_lines_past_the_end(self) -> None:
        reader = SourceReader(highlighter=lambda _path, text: text.splitlines())
        view = reader.read_view(str(self.path), 999, before=1, after=1)
        assert view is not None
        self.assertEqual(view.line, 20)
        self.assertEqual([line.number for line in view.lines], [19, 20])

    def test_current_text_stays_raw_when_highlighting_adds_ansi(self) -> None:
        reader = SourceReader(
            highlighter=lambda _path, text: [
                f"\x1b[32m{line}\x1b[0m" for line in text.splitlines()
            ]
        )
        view = reader.read_view(str(self.path), 2, before=0, after=0)
        assert view is not None
        self.assertEqual(view.current_text, "line 2")
        self.assertIn("\x1b[32m", view.lines[0].text)

    def test_colour_can_be_disabled_for_the_source_pane(self) -> None:
        reader = SourceReader(color=False)
        view = reader.read_view(str(self.path), 2, before=0, after=0)
        assert view is not None
        self.assertEqual(view.lines[0].text, "line 2")

    def test_missing_file_returns_none(self) -> None:
        reader = SourceReader(highlighter=lambda _path, text: text.splitlines())
        self.assertIsNone(reader.read_view(str(self.path) + ".missing", 1))

    def test_display_path_keeps_absolute_paths_outside_the_project(self) -> None:
        outside = os.path.join(os.sep, "tmp", "outside.s")
        self.assertEqual(display_path(outside), outside)


if __name__ == "__main__":
    unittest.main()
