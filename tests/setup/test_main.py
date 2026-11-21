from __future__ import annotations

import unittest
from types import SimpleNamespace

from provision.main import should_prompt


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


if __name__ == "__main__":
    unittest.main()
