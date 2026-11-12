import tempfile
import unittest
from pathlib import Path

from provision.migrations.core import nvim_plugins_bootstrapped


class NvimBootstrapCheckTest(unittest.TestCase):
    def test_rpi_marker_skips_bootstrap(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "rpi-issue"
            marker.write_text("", encoding="utf-8")
            self.assertTrue(nvim_plugins_bootstrapped(home, marker))

    def test_lazy_dir_means_bootstrapped(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "missing-marker"
            (home / ".local" / "share" / "nvim" / "lazy").mkdir(parents=True)
            self.assertTrue(nvim_plugins_bootstrapped(home, marker))

    def test_nothing_installed(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            marker = home / "missing-marker"
            self.assertFalse(nvim_plugins_bootstrapped(home, marker))


if __name__ == "__main__":
    unittest.main()
