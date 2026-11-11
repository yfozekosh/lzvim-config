from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.models import Migration, MigrationLog


class MigrationLogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "log"
        self.log = MigrationLog(self.path)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_old_lines_without_verb_are_apply(self) -> None:
        self.path.write_text("install_dotnet 2026-01-01 'Linux test'\n", encoding="utf-8")
        log = MigrationLog(self.path)
        self.assertTrue(log.is_applied("install_dotnet"))

    def test_last_record_wins(self) -> None:
        self.log.apply("install_dotnet")
        self.assertTrue(self.log.is_applied("install_dotnet"))
        self.log.undo("install_dotnet")
        self.assertFalse(self.log.is_applied("install_dotnet"))
        self.log.apply("install_dotnet")
        self.assertTrue(self.log.is_applied("install_dotnet"))

    def test_log_is_append_only(self) -> None:
        self.log.apply("x")
        self.log.undo("x")
        lines = self.path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith("apply x "))
        self.assertTrue(lines[1].startswith("undo x "))


class MigrationLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.log = MigrationLog(Path(self.tmp.name) / "log")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_run_up_and_down_record_state(self) -> None:
        calls: list[str] = []
        migration = Migration(
            "demo",
            "core",
            lambda: calls.append("up"),
            lambda: calls.append("down"),
        )
        migration.run_up(self.log)
        self.assertEqual(calls, ["up"])
        self.assertTrue(self.log.is_applied("demo"))
        migration.run_down(self.log)
        self.assertEqual(calls, ["up", "down"])
        self.assertFalse(self.log.is_applied("demo"))


if __name__ == "__main__":
    unittest.main()
