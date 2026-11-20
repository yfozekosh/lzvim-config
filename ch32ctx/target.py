"""GDB adapter for the CH32V003 context view.

Only this module imports :mod:`gdb`.  Everything else is plain Python and can
be exercised without a debugger or a target.
"""

from __future__ import annotations

import re
import struct

import gdb  # type: ignore[import-not-found]

from .model import Dereference, Instruction, Register, Section, SourceView, StackEntry
from .source import SourceReader
from .window import select_window

# RV32EC exposes these sixteen registers.  ``$pc`` is intentionally absent:
# the code pane is the canonical place for the program counter.
REGISTERS = (
    "$zero",
    "$ra",
    "$sp",
    "$gp",
    "$tp",
    "$t0",
    "$t1",
    "$t2",
    "$fp",
    "$s1",
    "$a0",
    "$a1",
    "$a2",
    "$a3",
    "$a4",
    "$a5",
)

FLASH_START = 0x00000000
FLASH_END = 0x00004000
FLASH_ALIAS_START = 0x08000000
FLASH_ALIAS_END = 0x08004000
RAM_START = 0x20000000
RAM_END = 0x20000800
APB_START = 0x40000000
APB_END = 0x40030000
CORE_START = 0xE0000000
CORE_END = 0xE0010000
INFO_RANGES = (
    (0x1FFFF704, 0x1FFFF708, "ESIG"),
    (0x1FFFF7E0, 0x1FFFF7F4, "INFO"),
    (0x1FFFF800, 0x1FFFF80C, "OPTION"),
)

_STRING_MAX = 32
_STRING_MIN = 3


def _is_flash_address(value: int) -> bool:
    """Return whether *value* points into the CH32V003 flash windows."""

    return FLASH_START <= value < FLASH_END or (
        FLASH_ALIAS_START <= value < FLASH_ALIAS_END
    )


_SECTION_RE = re.compile(
    r"^\s*\[\d+\]\s+(0x[0-9a-fA-F]+)->(0x[0-9a-fA-F]+)"
    r"(?:\s+at\s+\S+)?:\s+(\S+)\s*(.*)$"
)

_FIXED_SECTIONS = (
    Section(FLASH_START, FLASH_END, ".text", readable=True, executable=True),
    Section(
        FLASH_ALIAS_START,
        FLASH_ALIAS_END,
        ".flash-alias",
        readable=True,
        executable=True,
    ),
    *(Section(start, end, name, readable=True) for start, end, name in INFO_RANGES),
    # Four bytes past the physical end let the first stack read at _stack_top
    # be classified; the actual read still fails safely when unmapped.
    Section(RAM_START, RAM_END + 4, ".sram", readable=True, writable=True),
    Section(APB_START, APB_END, "APB", readable=True, writable=True),
    Section(CORE_START, CORE_END, "core", readable=True, writable=True),
)


_REGISTER_NAMES = tuple(name.lstrip("$") for name in REGISTERS)
_MMIO_RANGES = (
    (APB_START, APB_END),
    (CORE_START, CORE_END),
)


def _mask32(value: int) -> int:
    return value & 0xFFFFFFFF


def _is_mmio(address: int) -> bool:
    """Return whether *address* belongs to a memory-mapped peripheral."""

    return any(start <= address < end for start, end in _MMIO_RANGES)


def _parse_register_dump(output: str) -> dict[str, int]:
    """Parse the second column of GDB's ``info registers`` output.

    The output is stable across remote and native targets: one register per
    line, followed by its value.  Parsing it here lets the target read every
    core register with a single remote ``g`` packet instead of one round-trip
    per register.
    """

    values: dict[str, int] = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        name = fields[0].lstrip("$")
        if name not in _REGISTER_NAMES and name != "pc":
            continue
        try:
            values[name] = _mask32(int(fields[1], 0))
        except ValueError:
            continue
    return values


class GdbTarget:
    """Read the live target through GDB's Python API."""

    def __init__(self, source: SourceReader | None = None) -> None:
        self._source = source or SourceReader()
        self._symbols: dict[int, str | None] = {}
        self._sections: list[Section] | None = None
        self._register_values: dict[str, int] | None = None
        self._previous_registers: dict[str, int] | None = None
        self.dereference_enabled = True
        self.mmio_enabled = False

    def invalidate(self) -> None:
        """Drop caches that depend on the loaded ELF or live target."""

        self._symbols.clear()
        self._sections = None
        self._register_values = None

    def _read_register_values(self) -> dict[str, int]:
        """Read all core registers with one GDB register fetch."""

        if self._register_values is not None:
            return self._register_values

        values: dict[str, int] = {}
        try:
            values = _parse_register_dump(gdb.execute("info registers", to_string=True))
        except (gdb.error, TypeError):
            values = {}

        # Fall back only for registers absent from the dump.  This keeps
        # targets with an unusual register layout working without giving up
        # the single-fetch fast path.
        for name in REGISTERS:
            key = name.lstrip("$")
            if key in values:
                continue
            try:
                values[key] = _mask32(int(gdb.parse_and_eval(name)))
            except (gdb.error, ValueError, TypeError):
                continue

        self._register_values = values
        return values

    def current_pc(self) -> int | None:
        values = self._read_register_values()
        if "pc" in values:
            return values["pc"]
        try:
            value = gdb.parse_and_eval("$pc")
            if value.type.code == gdb.TYPE_CODE_VOID:
                return None
            return _mask32(int(value))
        except (gdb.error, ValueError, TypeError):
            return None

    def registers(self) -> list[Register]:
        values = self._read_register_values()
        previous = self._previous_registers
        result: list[Register] = []
        current: dict[str, int] = {}
        for name in REGISTERS:
            key = name.lstrip("$")
            if key not in values:
                continue
            value = values[key]
            current[key] = value
            dereference = self._dereference(value) if self.dereference_enabled else None
            symbol = (
                self.symbol_at(value) if value and _is_flash_address(value) else None
            )
            result.append(
                Register(
                    name=name,
                    value=value,
                    dereference=dereference,
                    symbol=symbol,
                    changed=previous is not None and previous.get(key) != value,
                )
            )
        self._previous_registers = current
        return result

    def read_bytes(self, address: int, count: int) -> bytes | None:
        if address < 0 or count <= 0:
            return None
        try:
            return bytes(gdb.selected_inferior().read_memory(address, count).tobytes())
        except (gdb.error, gdb.MemoryError, OverflowError):
            return None

    def read_word(self, address: int) -> int | None:
        raw = self.read_bytes(address, 4)
        if raw is None or len(raw) != 4:
            return None
        return struct.unpack("<I", raw)[0]

    def sections(self) -> list[Section]:
        if self._sections is not None:
            return self._sections
        parsed: list[Section] = []
        try:
            output = gdb.execute("maintenance info sections", to_string=True)
        except gdb.error:
            output = ""
        for line in output.splitlines():
            match = _SECTION_RE.match(line)
            if match is None:
                continue
            start = int(match.group(1), 16)
            end = int(match.group(2), 16)
            name = match.group(3)
            flags = match.group(4)
            if end <= start or "ALLOC" not in flags:
                continue
            parsed.append(
                Section(
                    start=start,
                    end=end,
                    name=name,
                    readable=True,
                    writable="DATA" in flags and "READONLY" not in flags,
                    executable="CODE" in flags,
                )
            )
        self._sections = parsed + list(_FIXED_SECTIONS)
        return self._sections

    def section_for(self, address: int) -> Section | None:
        if address < 0:
            return None
        for section in self.sections():
            if section.readable and section.start <= address < section.end:
                return section
        return None

    def symbol_at(self, address: int) -> str | None:
        if address in self._symbols:
            return self._symbols[address]
        try:
            output = gdb.execute(f"info symbol {address:#x}", to_string=True).strip()
        except gdb.error:
            output = ""
        if not output or output.startswith("No symbol"):
            self._symbols[address] = None
            return None
        name = output.split(" in section ", 1)[0].strip()
        name = name.replace(" + ", "+")
        self._symbols[address] = name or None
        return self._symbols[address]

    def _dereference(self, address: int) -> Dereference | None:
        if not self.dereference_enabled:
            return None
        if _is_mmio(address) and not self.mmio_enabled:
            # Reading peripheral registers can have side effects (clear-on-
            # read bits, FIFOs, and similar).  The context view is a debugger
            # observer, so it must not touch MMIO unless explicitly asked to.
            return None
        if self.section_for(address) is None:
            return None
        word = self.read_word(address)
        if word is None:
            return None
        return Dereference(
            address=address, word=word, text=self._string_at(address, word)
        )

    def _string_at(self, address: int, word: int) -> str | None:
        """Return a NUL-terminated printable string at *address*, if any.

        Only readable data sections qualify: code bytes often happen to be
        printable, and treating them as strings makes register labels lie.
        The first word is inspected before a longer read so zeroed memory does
        not cause an extra target transaction on every register.
        """

        section = self.section_for(address)
        if section is None or section.executable:
            return None

        initial = struct.pack("<I", word)
        prefix = bytearray()
        for index, byte in enumerate(initial):
            if byte == 0:
                if index < _STRING_MIN:
                    return None
                return bytes(prefix).decode("ascii")
            if not 0x20 <= byte <= 0x7E:
                return None
            prefix.append(byte)

        limit = min(_STRING_MAX, section.end - address)
        if limit <= len(initial):
            return None
        raw = self.read_bytes(address, limit)
        if raw is None:
            return None
        end = raw.find(b"\x00")
        if end < _STRING_MIN:
            return None
        chunk = raw[:end]
        if any(byte < 0x20 or byte > 0x7E for byte in chunk):
            return None
        return chunk.decode("ascii")

    def instructions(
        self, pc: int, previous: int = 4, following: int = 6
    ) -> list[Instruction]:
        start = max(0, pc - 32)
        end = max(pc + 64, start + 1)
        try:
            decoded = gdb.selected_inferior().architecture().disassemble(start, end)
        except (gdb.error, OverflowError):
            return []

        # One read covers the whole disassembly window.  Falling back to a
        # per-instruction read only when the window itself is not contiguous
        # keeps the common case to a single remote transaction.
        blob = self.read_bytes(start, end - start)
        instructions: list[Instruction] = []
        for item in decoded:
            address = int(item["addr"])
            length = int(item.get("length", 4))
            opcode = b""
            offset = address - start
            if blob is not None and 0 <= offset and offset + length <= len(blob):
                opcode = blob[offset : offset + length]
            else:
                opcode = self.read_bytes(address, length) or b""
            instructions.append(
                Instruction(
                    address=address,
                    asm=" ".join(str(item.get("asm", "")).replace("\t", " ").split()),
                    length=length,
                    opcode=opcode.hex() if opcode else "",
                    symbol=self.symbol_at(address) if address == pc else None,
                )
            )
        return select_window(instructions, pc, previous=previous, following=following)

    def source_view(
        self,
        pc: int,
        before: int = 5,
        after: int = 5,
    ) -> SourceView | None:
        try:
            line = gdb.find_pc_line(pc)
        except gdb.error:
            return None
        if line.symtab is None or line.line <= 0:
            return None
        try:
            path = line.symtab.fullname()
        except (gdb.error, AttributeError):
            return None
        if not path:
            return None
        return self._source.read_view(path, line.line, before=before, after=after)

    def stack(self, sp: int, count: int = 8) -> list[StackEntry]:
        if sp <= 0 or count <= 0:
            return []
        lowest = max(0, sp - count * 4)
        addresses = list(range(sp - 4, lowest - 1, -4))
        window = self.read_bytes(lowest, sp - lowest)
        entries: list[StackEntry] = []
        for address in addresses:
            value: int | None = None
            if window is not None:
                offset = address - lowest
                if 0 <= offset and offset + 4 <= len(window):
                    value = struct.unpack_from("<I", window, offset)[0]
            if value is None:
                value = self.read_word(address)
            dereference = self._dereference(value) if value is not None else None
            entries.append(
                StackEntry(
                    address=address,
                    offset=address - lowest,
                    value=value,
                    dereference=dereference,
                )
            )
        return entries

    def stack_pointer(self) -> int | None:
        values = self._read_register_values()
        if "sp" in values:
            return values["sp"]
        try:
            return _mask32(int(gdb.parse_and_eval("$sp")))
        except (gdb.error, ValueError, TypeError):
            return None
