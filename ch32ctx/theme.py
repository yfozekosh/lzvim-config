"""ANSI styling used by the CH32V003 context view.

The module is deliberately free of GDB imports so the formatting code can be
tested with plain Python.
"""

from __future__ import annotations

from dataclasses import dataclass

RESET = "\x1b[0m"

# SGR parameters.  Keep these names semantic so the formatting code does not
# grow a collection of one-off escape sequences.
BOLD = "1"
DIM = "2"
RED = "31"
GREEN = "32"
YELLOW = "33"
BLUE = "34"
MAGENTA = "35"
CYAN = "36"
GRAY = "90"


@dataclass(frozen=True)
class Theme:
    """Apply ANSI attributes to text, or return it untouched."""

    enabled: bool = True

    def style(self, text: str, *codes: str) -> str:
        """Return *text* wrapped in the given SGR codes.

        Empty text is returned unchanged: adding a reset before the first
        visible character would leak an escape into otherwise plain output.
        """

        if not self.enabled or not codes or not text:
            return text
        prefix = "".join(f"\x1b[{code}m" for code in codes)
        return prefix + text + RESET
