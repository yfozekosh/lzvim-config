from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.migrations import shell
from provision.models import MigrationLog, SetupContext


class BleshCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.home.mkdir()
        self.ctx = SetupContext(
            repo=root / "repo",
            home=self.home,
            distro="fedora",
            purge=False,
            desired={"shell"},
            log=MigrationLog(root / "migration.log"),
            profile_name="custom",
        )
        self.check = next(
            item for item in shell.build(self.ctx) if item.name == "install_blesh"
        ).check

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_bashrc(self) -> None:
        (self.home / ".bashrc").write_text(
            "source -- ~/.local/share/blesh/ble.sh\n", encoding="utf-8"
        )

    def write_ble(self, text: str) -> None:
        ble_sh = self.home / ".local" / "share" / "blesh" / "ble.sh"
        ble_sh.parent.mkdir(parents=True, exist_ok=True)
        ble_sh.write_text(text, encoding="utf-8")

    def test_missing_install_is_not_applied(self) -> None:
        self.assertFalse(self.check())

        self.write_bashrc()
        self.assertFalse(self.check())

        self.write_ble("# ble.sh 0.3.x has no ble-face command\n")
        self.assertFalse(self.check())

        self.write_ble("function ble-face { :; }\n")
        self.assertTrue(self.check())

    def test_source_line_is_required(self) -> None:
        self.write_ble("function ble-face { :; }\n")
        self.assertFalse(self.check())

        self.write_bashrc()
        self.assertTrue(self.check())


if __name__ == "__main__":
    unittest.main()
