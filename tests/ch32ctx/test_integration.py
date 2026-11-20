from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LOADER = REPO_ROOT / "ch32ctx.gdb"


def gdb_binary() -> str | None:
    found = shutil.which("riscv-wch-elf-gdb")
    if found:
        return found
    candidate = Path.home() / ".local" / "bin" / "riscv-wch-elf-gdb"
    if candidate.exists():
        return str(candidate)
    return None


class GdbIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        binary = gdb_binary()
        if binary is None:
            raise unittest.SkipTest("riscv-wch-elf-gdb is not installed")
        cls.binary = binary

    def run_gdb(self, *commands: str) -> subprocess.CompletedProcess[str]:
        args = [self.binary, "-nx", "-batch"]
        for command in commands:
            args.extend(["-ex", command])
        return subprocess.run(
            args, check=False, text=True, capture_output=True, timeout=30
        )

    def test_loader_registers_the_context_command(self) -> None:
        result = self.run_gdb(
            f"source {LOADER}",
            "python import ch32ctx; print('VERSION', ch32ctx.__version__)",
            "ctx help",
            "ctx off",
            "ctx",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VERSION 1.2.0", result.stdout)
        self.assertIn("usage: ctx", result.stdout)
        self.assertIn("automatic context off", result.stdout)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
