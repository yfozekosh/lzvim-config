from __future__ import annotations

import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from provision.main import parse_args, should_prompt


def args(**overrides):
    values = {
        "all": False,
        "profile": None,
        "features": None,
        "interactive": False,
        "noninteractive": False,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


class PromptTests(unittest.TestCase):
    def test_tty_prompts_on_every_run(self) -> None:
        self.assertTrue(should_prompt(args(), stdin_is_tty=True))

    def test_non_tty_does_not_prompt(self) -> None:
        self.assertFalse(should_prompt(args(), stdin_is_tty=False))

    def test_noninteractive_skips_prompt(self) -> None:
        self.assertFalse(should_prompt(args(noninteractive=True), stdin_is_tty=True))

    def test_explicit_selection_skips_prompt(self) -> None:
        for flags in (
            {"all": True},
            {"profile": "minimal"},
            {"features": "core,git"},
        ):
            with self.subTest(flags=flags):
                self.assertFalse(should_prompt(args(**flags), stdin_is_tty=True))

    def test_interactive_forces_prompt(self) -> None:
        self.assertTrue(should_prompt(args(interactive=True), stdin_is_tty=False))
        self.assertTrue(
            should_prompt(args(interactive=True, profile="minimal"), stdin_is_tty=False)
        )


class PurgeDefaultTests(unittest.TestCase):
    def test_purge_is_on_by_default(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(parse_args([]).purge)

    def test_no_purge_disables_it(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(parse_args(["--no-purge"]).purge)

    def test_purge_flag_stays_valid(self) -> None:
        with patch.dict(os.environ, {"SETUP_PURGE": "0"}, clear=True):
            self.assertTrue(parse_args(["--purge"]).purge)

    def test_env_can_disable_purge(self) -> None:
        for value in ("0", "false", "no", "off"):
            with self.subTest(value=value):
                with patch.dict(os.environ, {"SETUP_PURGE": value}, clear=True):
                    self.assertFalse(parse_args([]).purge)


if __name__ == "__main__":
    unittest.main()
