from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.features import FEATURES
from provision.migrations import ai, core, embedded, gef, git, nvim, wsl
from provision.models import MigrationLog, SetupContext

EXPECTED = {
    "core": {"install_packages"},
    "nvim": {"bootstrap_nvim_plugins", "prune_nvim_state"},
    "git": {"install_gh_cli", "install_lazygit"},
    "ai": {
        "install_copilot_cli",
        "configure_claude_statusline",
        "install_copilot_usage_scraper",
        "link_copilot_configs",
    },
    "embedded": {"install_asm_lsp", "install_rvfmt", "link_riscv_asm_configs"},
    "gef": {"install_gef", "link_gef_configs"},
    "wsl": {
        "install_wsl_fonts",
        "install_win32yank",
        "fix_wsl_interop_persistence",
    },
}


class MigrationOwnershipTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.ctx = SetupContext(
            repo=root / "repo",
            home=root / "home",
            distro="fedora",
            purge=False,
            desired=set(),
            log=MigrationLog(root / "migration.log"),
            profile_name="custom",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_modules_expose_expected_migrations(self) -> None:
        for module, expected in (
            (core, EXPECTED["core"]),
            (nvim, EXPECTED["nvim"]),
            (git, EXPECTED["git"]),
            (ai, EXPECTED["ai"]),
            (embedded, EXPECTED["embedded"]),
            (gef, EXPECTED["gef"]),
            (wsl, EXPECTED["wsl"]),
        ):
            names = {migration.name for migration in module.build(self.ctx)}
            self.assertEqual(names, expected, module.__name__)

    def test_every_migration_belongs_to_a_known_feature(self) -> None:
        for module in (core, nvim, git, ai, embedded, gef, wsl):
            for migration in module.build(self.ctx):
                self.assertIn(migration.feature, FEATURES, migration.name)

    def test_split_features_have_expected_owners(self) -> None:
        owners = {
            migration.name: migration.feature
            for module in (core, nvim, git, ai, embedded, gef, wsl)
            for migration in module.build(self.ctx)
        }
        self.assertEqual(owners["install_lazygit"], "git")
        self.assertEqual(owners["install_copilot_cli"], "copilot")
        self.assertEqual(owners["configure_claude_statusline"], "claude")
        self.assertEqual(owners["install_copilot_usage_scraper"], "copilot-usage")
        self.assertEqual(owners["install_asm_lsp"], "riscv-asm")
        self.assertEqual(owners["install_rvfmt"], "riscv-asm")
        self.assertEqual(owners["install_wsl_fonts"], "wsl-fonts")
        self.assertEqual(owners["install_win32yank"], "wsl-clipboard")
        self.assertEqual(owners["fix_wsl_interop_persistence"], "wsl-interop")


if __name__ == "__main__":
    unittest.main()
