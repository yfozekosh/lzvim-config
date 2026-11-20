from __future__ import annotations

import importlib
import struct
import sys
import types
import unittest
from typing import Any


class FakeGdbError(Exception):
    pass


class FakeMemoryError(FakeGdbError):
    pass


class FakeValue:
    def __init__(self, value: int) -> None:
        self._value = value
        self.type = types.SimpleNamespace(code=1)

    def __int__(self) -> int:
        return self._value


class FakeMemory:
    def __init__(self, chunks: dict[int, bytes]) -> None:
        self._chunks = chunks
        self.calls: list[tuple[int, int]] = []

    def read_memory(self, address: int, count: int) -> types.SimpleNamespace:
        self.calls.append((address, count))
        for start, data in self._chunks.items():
            end = start + len(data)
            if start <= address and address + count <= end:
                payload = data[address - start : address - start + count]
                return types.SimpleNamespace(tobytes=lambda payload=payload: payload)
        raise FakeMemoryError(f"cannot read {count} bytes at {address:#x}")


class FakeArchitecture:
    def __init__(self, instructions: list[dict[str, Any]]) -> None:
        self._instructions = instructions

    def disassemble(self, start: int, end: int) -> list[dict[str, Any]]:
        return [item for item in self._instructions if start <= int(item["addr"]) < end]


class FakeInferior:
    def __init__(self, memory: FakeMemory, instructions: list[dict[str, Any]]) -> None:
        self._memory = memory
        self._architecture = FakeArchitecture(instructions)

    def read_memory(self, address: int, count: int) -> types.SimpleNamespace:
        return self._memory.read_memory(address, count)

    def architecture(self) -> FakeArchitecture:
        return self._architecture


class FakeGdb(types.ModuleType):
    TYPE_CODE_VOID = 0
    error = FakeGdbError
    MemoryError = FakeMemoryError

    def __init__(
        self,
        registers: dict[str, int],
        memory: FakeMemory,
        instructions: list[dict[str, Any]],
        sections: str = "",
        symbols: dict[int, str] | None = None,
    ) -> None:
        super().__init__("gdb")
        self._registers = registers
        self._inferior = FakeInferior(memory, instructions)
        self._sections = sections
        self._symbols = symbols or {}

    def parse_and_eval(self, expression: str) -> FakeValue:
        try:
            return FakeValue(self._registers[expression])
        except KeyError as error:
            raise FakeGdbError(f"no register {expression}") from error

    def selected_inferior(self) -> FakeInferior:
        return self._inferior

    def execute(self, command: str, to_string: bool = False) -> str:
        if command == "maintenance info sections":
            return self._sections
        if command.startswith("info symbol "):
            address = int(command.rsplit(" ", 1)[1], 16)
            return self._symbols.get(address, "No symbol matches.\n")
        return ""


def _load_target(fake: FakeGdb):
    previous = sys.modules.get("gdb")
    sys.modules["gdb"] = fake
    sys.modules.pop("ch32ctx.target", None)
    try:
        module = importlib.import_module("ch32ctx.target")
    finally:
        if previous is None:
            sys.modules.pop("gdb", None)
        else:
            sys.modules["gdb"] = previous
    return module


def _word(value: int) -> bytes:
    return struct.pack("<I", value)


class TargetTests(unittest.TestCase):
    def build(
        self,
        registers: dict[str, int] | None = None,
        memory: dict[int, bytes] | None = None,
        instructions: list[dict[str, Any]] | None = None,
        sections: str = "",
        symbols: dict[int, str] | None = None,
    ):
        fake = FakeGdb(
            registers or {},
            FakeMemory(memory or {}),
            instructions or [],
            sections,
            symbols,
        )
        module = _load_target(fake)
        target = module.GdbTarget(module.SourceReader(color=False))
        target._test_memory = fake.selected_inferior()._memory  # type: ignore[attr-defined]
        return module, target

    def test_current_pc_is_masked_and_missing_target_is_none(self) -> None:
        _module, target = self.build(registers={"$pc": 0xFFFFFFFF})
        self.assertEqual(target.current_pc(), 0xFFFFFFFF)

        _, empty = self.build()
        self.assertIsNone(empty.current_pc())

    def test_registers_are_masked_and_only_mapped_values_dereference(self) -> None:
        _, target = self.build(
            registers={"$zero": 0, "$sp": 0x20000000, "$a0": 0xFFFFFFFF},
            memory={
                0: _word(0x02A0006F),
                0x20000000: _word(0x20000004),
            },
        )

        registers = target.registers()
        by_name = {register.name: register for register in registers}

        self.assertEqual(by_name["$zero"].value, 0)
        self.assertEqual(
            by_name["$zero"].dereference.word,
            0x02A0006F,
        )
        self.assertEqual(by_name["$a0"].value, 0xFFFFFFFF)
        self.assertIsNone(by_name["$a0"].dereference)
        self.assertIsNotNone(by_name["$sp"].dereference)

    def test_registers_label_nonzero_flash_values(self) -> None:
        _, target = self.build(
            registers={"$ra": 0x3A, "$a0": 0, "$gp": 0},
            symbols={0x3A: "_start + 16 in section .text\n"},
        )

        by_name = {register.name: register for register in target.registers()}

        self.assertEqual(by_name["$ra"].symbol, "_start+16")
        self.assertIsNone(by_name["$a0"].symbol)
        self.assertIsNone(by_name["$gp"].symbol)

    def test_dereference_reads_nul_terminated_ascii_strings(self) -> None:
        _, target = self.build(
            registers={"$a0": 0x20000000, "$a1": 0x20000010},
            memory={
                0x20000000: b"hello\x00" + b"\x00" * 32,
                0x20000010: b"o\x00" + b"\x00" * 32,
            },
        )

        by_name = {register.name: register for register in target.registers()}

        self.assertEqual(by_name["$a0"].dereference.text, "hello")
        self.assertIsNone(by_name["$a1"].dereference.text)

    def test_strings_are_not_read_from_executable_sections(self) -> None:
        sections = (
            " [0]      0x0000->0x0168 at 0x00001000: .text ALLOC LOAD "
            "READONLY CODE HAS_CONTENTS\n"
        )
        _, target = self.build(
            registers={"$a0": 0x100},
            memory={0x100: b"hello\x00" + b"\x00" * 32},
            sections=sections,
        )

        by_name = {register.name: register for register in target.registers()}

        self.assertIsNotNone(by_name["$a0"].dereference)
        self.assertIsNone(by_name["$a0"].dereference.text)

    def test_stack_window_ends_at_the_stack_pointer(self) -> None:
        _, target = self.build(
            registers={"$sp": 0x20000010},
            memory={
                0x2000000C: _word(1),
                0x20000008: _word(2),
            },
        )

        entries = target.stack(0x20000010, count=2)

        self.assertEqual([entry.address for entry in entries], [0x2000000C, 0x20000008])
        self.assertEqual([entry.offset for entry in entries], [4, 0])
        self.assertEqual([entry.value for entry in entries], [1, 2])

    def test_instructions_select_mixed_length_window(self) -> None:
        _, target = self.build(
            registers={"$pc": 0x80},
            memory={
                0x7C: b"\x6f\x00\x00\x00",
                0x80: b"\x33\xa3\xe2\xb3",
                0x84: b"\x01\x00",
            },
            instructions=[
                {"addr": 0x7C, "asm": "j 0x2a", "length": 4},
                {"addr": 0x80, "asm": "and t1,t1,t2", "length": 4},
                {"addr": 0x84, "asm": "nop", "length": 2},
            ],
            symbols={0x80: "_start + 16 in section .text\n"},
        )

        instructions = target.instructions(0x80, previous=1, following=1)

        self.assertEqual([item.address for item in instructions], [0x7C, 0x80, 0x84])
        self.assertTrue(instructions[1].is_current)
        self.assertEqual(instructions[1].symbol, "_start+16")
        self.assertEqual(instructions[1].opcode, "33a3e2b3")

    def test_sections_keep_alloc_sections_and_add_fixed_ranges(self) -> None:
        output = (
            " [0]      0x0000->0x0168 at 0x00001000: .text ALLOC LOAD "
            "READONLY CODE HAS_CONTENTS\n"
            " [1]      0x100000->0x100100 at 0x00002004: .debug_line "
            "READONLY HAS_CONTENTS\n"
        )
        _, target = self.build(sections=output)

        self.assertEqual(target.section_for(0x80).name, ".text")
        self.assertEqual(target.section_for(0x20000000).name, ".sram")
        self.assertEqual(target.section_for(0xE000F000).name, "core")
        self.assertIsNone(target.section_for(0x100000))

    def test_read_word_handles_unmapped_memory(self) -> None:
        _, target = self.build(memory={0x20000000: _word(0xCAFEBABE)})

        self.assertEqual(target.read_word(0x20000000), 0xCAFEBABE)
        self.assertIsNone(target.read_word(0x30000000))

    def test_register_dump_parser_accepts_info_registers_output(self) -> None:
        module, _target = self.build()
        output = (
            "zero           0x0                 0\n"
            "ra             0x3a                0x3a <_start+16>\n"
            "sp             0x20000800          0x20000800\n"
            "pc             0x3a                0x3a <_start+16>\n"
        )

        self.assertEqual(
            module._parse_register_dump(output),
            {"zero": 0, "ra": 0x3A, "sp": 0x20000800, "pc": 0x3A},
        )

    def test_mmio_dereferences_are_opt_in(self) -> None:
        _, target = self.build(
            registers={"$t0": 0xE000F010},
            memory={0xE000F010: _word(0x12345678)},
        )
        by_name = {register.name: register for register in target.registers()}
        self.assertIsNone(by_name["$t0"].dereference)

        target.mmio_enabled = True
        by_name = {register.name: register for register in target.registers()}
        self.assertEqual(by_name["$t0"].dereference.word, 0x12345678)

    def test_dereferences_can_be_disabled(self) -> None:
        _, target = self.build(
            registers={"$sp": 0x20000000},
            memory={0x20000000: _word(0xCAFEBABE)},
        )
        target.dereference_enabled = False

        by_name = {register.name: register for register in target.registers()}

        self.assertIsNone(by_name["$sp"].dereference)

    def test_changed_registers_are_marked_between_fetches(self) -> None:
        _, target = self.build(
            registers={"$a0": 1, "$a1": 2},
        )
        first = {register.name: register for register in target.registers()}
        self.assertFalse(first["$a0"].changed)

        target._read_register_values()["a0"] = 9
        second = {register.name: register for register in target.registers()}

        self.assertTrue(second["$a0"].changed)
        self.assertFalse(second["$a1"].changed)

    def test_stack_window_is_read_in_one_transaction(self) -> None:
        _module, target = self.build(
            registers={"$sp": 0x20000010},
            memory={0x20000008: _word(1) + _word(2)},
        )

        entries = target.stack(0x20000010, count=2)

        self.assertEqual([entry.value for entry in entries], [2, 1])
        calls = target._test_memory.calls  # type: ignore[attr-defined]
        self.assertIn((0x20000008, 8), calls)


if __name__ == "__main__":
    unittest.main()
