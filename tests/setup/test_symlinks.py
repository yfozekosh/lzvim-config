from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.migrations import ai, core, embedded, gef, shell, tmux
from provision.models import MigrationLog, SetupContext

# (module, migration name, [(repo target, link under $HOME), ...])
FEATURE_LINKS = [
    (
        shell,
        "link_shell_configs",
        [
            (".bash_profile_yf", ".bash_profile_yf"),
            (".blerc", ".blerc"),
        ],
    ),
    (
        tmux,
        "link_tmux_configs",
        [
            (".tmux.conf", ".tmux.conf"),
            ("tmux-scripts", ".tmux/scripts"),
        ],
    ),
    (
        ai,
        "link_ai_configs",
        [("copilot-instructions.md", ".copilot/copilot-instructions.md")],
    ),
    (
        embedded,
        "link_embedded_configs",
        [
            ("asm-lsp/.asm-lsp.toml", ".config/asm-lsp/.asm-lsp.toml"),
            ("scripts/ld-format", ".local/bin/ld-format"),
        ],
    ),
    (gef, "link_gef_configs", [(".gdbinit", ".gdbinit")]),
]


class SymlinkMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.home = self.root / "home"
        self.repo.mkdir()
        self.home.mkdir()
        self.ctx = SetupContext(
            repo=self.repo,
            home=self.home,
            distro="fedora",
            purge=False,
            desired=set(),
            log=MigrationLog(self.root / "migration.log"),
            profile_name="custom",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def migration(self, module, name: str):
        return next(item for item in module.build(self.ctx) if item.name == name)

    def create_target(self, relative: str) -> Path:
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("", encoding="utf-8")
        return target

    def test_each_feature_owns_and_removes_its_links(self) -> None:
        for module, name, links in FEATURE_LINKS:
            migration = self.migration(module, name)
            self.assertFalse(migration.check(), name)
            for relative, link_relative in links:
                target = self.create_target(relative)
                link = self.home / link_relative
                migration.up()
                self.assertTrue(link.is_symlink(), f"{name}: {link}")
                self.assertEqual(link.readlink(), target)
                self.assertTrue(migration.check(), name)
            migration.down()
            for _, link_relative in links:
                link = self.home / link_relative
                self.assertFalse(link.is_symlink(), f"{name}: {link}")
            self.assertFalse(migration.check(), name)

    def test_down_removes_only_links_pointing_at_the_repo(self) -> None:
        migration = self.migration(tmux, "link_tmux_configs")
        foreign = self.root / "foreign.conf"
        foreign.write_text("", encoding="utf-8")
        link = self.home / ".tmux.conf"
        link.symlink_to(foreign)

        migration.down()

        self.assertTrue(link.is_symlink())
        self.assertEqual(link.readlink(), foreign)

    def test_up_replaces_foreign_symlink(self) -> None:
        migration = self.migration(tmux, "link_tmux_configs")
        target = self.create_target(".tmux.conf")
        foreign = self.root / "foreign.conf"
        foreign.write_text("", encoding="utf-8")
        link = self.home / ".tmux.conf"
        link.symlink_to(foreign)

        migration.up()

        self.assertEqual(link.readlink(), target)
        self.assertTrue(foreign.is_file())

    def test_core_no_longer_owns_symlinks(self) -> None:
        names = {item.name for item in core.build(self.ctx)}
        self.assertNotIn("link_configs", names)
        self.assertNotIn("repair_config_symlinks", names)


if __name__ == "__main__":
    unittest.main()
