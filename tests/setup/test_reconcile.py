from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from provision.main import reconcile
from provision.models import Migration, MigrationLog


class ReconcileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.log = MigrationLog(Path(self.tmp.name) / "log")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def make_migration(self, check=lambda: False):
        calls: list[str] = []
        migration = Migration(
            "demo",
            "core",
            lambda: calls.append("up"),
            lambda: calls.append("down"),
            check,
        )
        return migration, calls

    def test_selected_not_applied_runs_up(self) -> None:
        migration, calls = self.make_migration()
        with redirect_stdout(io.StringIO()):
            reconcile([migration], {"core"}, self.log)
        self.assertEqual(calls, ["up"])
        self.assertTrue(self.log.is_applied("demo"))

    def test_selected_already_applied_reruns_up_without_new_record(self) -> None:
        migration, calls = self.make_migration()
        self.log.apply("demo")
        with redirect_stdout(io.StringIO()):
            reconcile([migration], {"core"}, self.log)
        self.assertEqual(calls, ["up"])
        self.assertEqual(sum(1 for r in self.log.records if r.name == "demo"), 1)

    def test_unselected_applied_runs_down(self) -> None:
        migration, calls = self.make_migration()
        self.log.apply("demo")
        with redirect_stdout(io.StringIO()):
            reconcile([migration], set(), self.log)
        self.assertEqual(calls, ["down"])
        self.assertFalse(self.log.is_applied("demo"))

    def test_unselected_not_applied_but_present_runs_down(self) -> None:
        migration, calls = self.make_migration(check=lambda: True)
        with redirect_stdout(io.StringIO()):
            reconcile([migration], set(), self.log)
        self.assertEqual(calls, ["down"])
        self.assertFalse(self.log.is_applied("demo"))


if __name__ == "__main__":
    unittest.main()
