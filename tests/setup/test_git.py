from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from provision.migrations import git
from provision.models import MigrationLog, SetupContext


class LazygitMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.ctx = SetupContext(
            repo=root / "repo",
            home=root / "home",
            distro="fedora",
            purge=False,
            desired={"git"},
            log=MigrationLog(root / "migration.log"),
            profile_name="custom",
        )
        self.migration = next(
            item for item in git.build(self.ctx) if item.name == "install_lazygit"
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_enable_copr_with_sudo(self) -> None:
        with (
            patch.object(git, "cmd_exists", return_value=False),
            patch.object(git, "sudo", side_effect=lambda cmd: ["sudo", *cmd]),
            patch.object(git, "run") as run_mock,
            patch.object(git, "dnf_install") as install_mock,
        ):
            self.migration.up()

        run_mock.assert_called_once_with(
            ["sudo", "dnf", "copr", "enable", "-y", "atim/lazygit"]
        )
        install_mock.assert_called_once_with(["lazygit"])

    def test_already_installed_is_left_alone(self) -> None:
        with (
            patch.object(git, "cmd_exists", return_value=True),
            patch.object(git, "run") as run_mock,
            patch.object(git, "dnf_install") as install_mock,
        ):
            self.migration.up()

        run_mock.assert_not_called()
        install_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
