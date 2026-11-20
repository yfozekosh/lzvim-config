from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from provision.migrations.gef import GEF_BRANCH, GEF_REPO, build, is_installed, is_our_checkout
from provision.models import MigrationLog, SetupContext


class GefMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.target = self.home / ".local" / "share" / "gef"
        self.ctx = SetupContext(
            repo=self.home,
            home=self.home,
            distro="fedora",
            purge=False,
            desired={"gef"},
            log=MigrationLog(self.home / "migration.log"),
            profile_name="custom",
        )
        self.migration = build(self.ctx)[0]

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def install(self) -> None:
        self.target.mkdir(parents=True)
        (self.target / "gef.py").write_text("", encoding="utf-8")
        (self.target / "gef_riscv.py").write_text("", encoding="utf-8")

    def test_check_detects_both_scripts(self) -> None:
        self.assertFalse(self.migration.check())
        self.install()
        self.assertTrue(self.migration.check())
        self.assertTrue(is_installed(self.target))

    def test_up_skips_existing_install(self) -> None:
        self.install()
        with patch("provision.migrations.gef.run") as run:
            self.migration.up()
        run.assert_not_called()

    def test_up_clones_the_fork_branch(self) -> None:
        def fake_run(args, **kwargs):
            self.assertEqual(
                args,
                ["git", "clone", "--branch", GEF_BRANCH, "--depth", "1", GEF_REPO, str(self.target)],
            )
            self.target.mkdir(parents=True)
            (self.target / "gef.py").write_text("", encoding="utf-8")
            (self.target / "gef_riscv.py").write_text("", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with patch("provision.migrations.gef.run", side_effect=fake_run):
            self.migration.up()
        self.assertTrue(self.migration.check())

    def test_up_leaves_unrelated_directory_alone(self) -> None:
        self.target.mkdir(parents=True)
        with patch("provision.migrations.gef.run") as run:
            self.migration.up()
        run.assert_not_called()
        self.assertTrue(self.target.is_dir())

    def test_down_removes_only_our_checkout(self) -> None:
        self.target.mkdir(parents=True)
        subprocess.run(["git", "init", str(self.target)], check=True, capture_output=True)
        subprocess.run(
            ["git", "-C", str(self.target), "remote", "add", "origin", GEF_REPO],
            check=True,
            capture_output=True,
        )
        self.assertTrue(is_our_checkout(self.target))
        self.migration.down()
        self.assertFalse(self.target.exists())

    def test_down_keeps_development_symlink(self) -> None:
        checkout = self.home / "src" / "gef"
        checkout.mkdir(parents=True)
        (checkout / "gef.py").write_text("", encoding="utf-8")
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(checkout)
        self.migration.down()
        self.assertTrue(self.target.is_symlink())
        self.assertTrue((checkout / "gef.py").is_file())

    def test_down_keeps_directory_without_fork_origin(self) -> None:
        self.target.mkdir(parents=True)
        (self.target / "notes.txt").write_text("mine", encoding="utf-8")
        self.migration.down()
        self.assertTrue((self.target / "notes.txt").is_file())


if __name__ == "__main__":
    unittest.main()
