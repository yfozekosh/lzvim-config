from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.migrations.tmux import TMUX_MEM_CPU_LOAD_VERSION, binary_version


class BinaryVersionTests(unittest.TestCase):
    def test_reads_version_from_help_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "tmux-mem-cpu-load"
            binary.write_text(
                "#!/bin/sh\n"
                f"echo 'tmux-mem-cpu-load v{TMUX_MEM_CPU_LOAD_VERSION}'\n",
                encoding="utf-8",
            )
            binary.chmod(0o755)
            self.assertEqual(binary_version(binary), TMUX_MEM_CPU_LOAD_VERSION)

    def test_missing_binary_has_no_version(self) -> None:
        self.assertIsNone(binary_version(Path("/nonexistent/tmux-mem-cpu-load")))

    def test_unrecognized_output_has_no_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "tmux-mem-cpu-load"
            binary.write_text("#!/bin/sh\necho 'not a version'\n", encoding="utf-8")
            binary.chmod(0o755)
            self.assertIsNone(binary_version(binary))


if __name__ == "__main__":
    unittest.main()
