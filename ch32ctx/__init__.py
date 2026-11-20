"""A small, bare-metal GDB context view for the WCH CH32V003.

The package is imported by ``ch32ctx.gdb``.  Importing it does not touch GDB,
so the pure formatting modules remain usable from normal Python tests.
"""

from __future__ import annotations

__all__ = ["__version__", "install"]

__version__ = "1.2.0"


def install() -> None:
    """Install the ``ctx`` command and its automatic stop hook."""

    from .context import install as _install

    _install()
