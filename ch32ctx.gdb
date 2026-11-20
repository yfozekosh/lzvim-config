# Load the CH32V003 context view.
#
# Source this file from a GDB with Python support (the WCH toolchain GDB).
# Keeping it separate from .gdbinit lets the shared configuration stay usable
# with toolchains that were built without Python.

python
import os
import sys

_ch32ctx_root = os.path.expanduser("~/.config/nvim")
if _ch32ctx_root not in sys.path:
    sys.path.insert(0, _ch32ctx_root)
import ch32ctx
ch32ctx.install()
end
