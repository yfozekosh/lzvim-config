from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class DockerPanelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.root / "state"
        self.state.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.script = Path(__file__).resolve().parents[2] / "tmux-scripts" / "docker-panel.sh"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _path_with(self, *, docker: bool) -> str:
        for name in ("dirname", "grep"):
            source = shutil.which(name)
            if source:
                (self.bin / name).symlink_to(source)
        if docker:
            fake = self.bin / "docker"
            fake.write_text("#!/bin/sh\nprintf 'abc\\ndef\\n'\n", encoding="utf-8")
            fake.chmod(0o755)
        return str(self.bin)

    def _run(self, features: str | None, *, docker: bool) -> str:
        if features is not None:
            (self.state / "features").write_text(features, encoding="utf-8")
        env = os.environ.copy()
        env["HOME"] = str(self.home)
        env["YF_NVIM_STATE_DIR"] = str(self.state)
        env["PATH"] = self._path_with(docker=docker)
        result = subprocess.run(
            [str(self.script)],
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        return result.stdout

    def test_enabled_shows_count(self) -> None:
        self.assertEqual(self._run("docker=on\n", docker=True), " Docker:[2]")

    def test_disabled_hides_panel_even_when_docker_exists(self) -> None:
        self.assertEqual(self._run("docker=off\n", docker=True), "")

    def test_enabled_shows_na_when_docker_is_missing(self) -> None:
        self.assertEqual(self._run("docker=on\n", docker=False), " Docker:[n/a]")

    def test_custom_selection_without_docker_stays_off(self) -> None:
        self.assertEqual(self._run("profile=custom\ncore=on\n", docker=True), "")

    def test_missing_selection_defaults_to_visible(self) -> None:
        self.assertEqual(self._run(None, docker=True), " Docker:[2]")


if __name__ == "__main__":
    unittest.main()
