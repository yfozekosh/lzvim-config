# ch32ctx — a CH32V003 context view for GDB

`ch32ctx` is a small, GEF-free context view for the WCH CH32V003. It prints the
state that matters while single-stepping a bare-metal RV32EC program:

- core registers in hex and unsigned decimal,
- the stack window below `$sp`,
- mixed 2/4-byte RISC-V disassembly around `$pc`,
- the assembler macro invoked by the current source line,
- the source lines around the current line.

It is an inline GDB view, not a full-screen TUI. It is designed for the WCH
toolchain GDB (`riscv-wch-elf-gdb`) that embeds Python 3.8, but the pure
formatting code is independent of GDB and is unit-tested without a target.

## Loading

The tracked `.gdbinit` loads the view automatically when GDB is the WCH
toolchain:

```gdb
# section 7 of ~/.config/nvim/.gdbinit
shell readlink /proc/$PPID/exe | grep -q wch-toolchain
if $_shell_exitcode == 0
    source ~/.config/nvim/ch32ctx.gdb
end
```

Start the project normally:

```bash
cd ~/Projects/mtrx_asm
make gdb
```

The xPack GDB and the system GDB are left untouched because neither provides
the required WCH Python environment. To load the view by hand in an already
running WCH GDB:

```gdb
source ~/.config/nvim/ch32ctx.gdb
```

After the project auto-connect, `ctx` prints once automatically. From then on
it prints after every stop: `step`, `stepi`, `next`, `finish`, `continue`
stops, breakpoints, watchpoints, signals, and `monitor reset halt`. It does not
print while the CPU is running freely.

## Commands

| Command | Effect |
| --- | --- |
| `ctx` | Print all panes. |
| `ctx registers` | Only the register pane. |
| `ctx stack` | Only the stack pane. |
| `ctx code` | Only the disassembly pane. |
| `ctx macro` | Only the macro pane. |
| `ctx source` | Only the source pane. |
| `ctx registers stack` | Any combination, in the requested order. |
| `ctx all` | Same as `ctx`. |
| `ctx off` | Stop the automatic output on stops. |
| `ctx on` | Resume the automatic output. |
| `ctx deref off` | Disable pointer/string previews (useful on a slow link). |
| `ctx deref on` | Re-enable pointer/string previews (default). |
| `ctx mmio on` | Allow automatic reads of APB/core peripheral addresses. |
| `ctx mmio off` | Block automatic MMIO reads (default). |
| `ctx help` | Show the command summary. |

Aliases: `regs` → `registers`, `disasm`/`disassembly` → `code`,
`src` → `source`, `macros` → `macro`.

`ctx off` only controls the stop hook. An explicit `ctx` still prints while
automatic output is disabled.

## Panes

### registers

Every RV32EC register is printed as:

```text
$ra  : 0x0000003a (        58) <_start+16>  → 0x00001234
$sp  : 0x20000800 ( 536872960)
$t0  : 0xe000f004 (3758157828)
```

- Hex and unsigned decimal are aligned.
- A non-zero value in the CH32V003 flash window is labelled with the nearest
  symbol from the ELF (`<_start+16>`, `<main+36>`, ...). Zero is never
  labelled; otherwise every zeroed register would look like a pointer to the
  vector table.
- `→` is a safe pointer preview: the word stored at the register value.
  A printable NUL-terminated ASCII string is appended when the target address
  is in a readable, non-executable section and contains at least three
  printable characters. Code bytes are never interpreted as strings.
- Registers are read with one `info registers` transaction per stop, rather
  than one remote round-trip per register. Changed values are rendered in
  bold yellow. The first view after loading has no "changed" state.

### stack

```text
0x200007fc│+0x001c: 0x0000074a
0x200007f8│+0x0018: 0x28c41320
...
0x200007e0│+0x0000: 0xa4486ff6
```

The window ends at `$sp` and walks downward. `+0x…` is the offset from the
lowest address in the window, matching GEF's stack layout. The whole window is
read with one `read_memory` call; the view falls back to per-word reads only
if the range is not readable. A word that cannot be read is shown as `??`.
Pointer previews use the same safe rules as registers.

At reset `$sp` is `0x20000800` (one past the last byte of SRAM), so the window
ends at the last readable word rather than trying to read at `$sp`.

### code

```text
=> 0x0000003a <_start+16>: 937203f7 li t2,-9
   0x0000003c: 33a3e2b3 and t1,t1,t2
```

The window is centered on `$pc` and uses GDB's architecture disassembler, so
compressed 2-byte and regular 4-byte instructions are handled correctly. The
current instruction has a green `=>`; previous instructions are dimmed.
Addresses, opcodes, and branch targets come from the ELF. Only the current
instruction gets a symbol label; branch instructions already carry their
target symbols from GDB.

### macro

When the current source line is an assembler macro invocation, the definition
is printed between the disassembly and the source panes:

```text
────────────────────────────────────────── macro:SET_CLOCK_8Mhz
  executing at src/boot.s:60
  defined at src/rcc.s:32
  32  .macro SET_CLOCK_8Mhz
  33      # clear first two bits of the clock configuration register
  34      la t0, RCC_CTLR
  ...
  56  .endm
```

- The index scans the project's `src/**/*.s` and `*.inc` files, so definitions
  in included files (`rcc.s`, `stk.s`, ...) are found even when the invocation
  is in `boot.s`.
- Invocation arguments and definition parameters are shown when present.
- The pane is omitted when the current line is not a macro call, or when no
  definition is found.
- DWARF maps every instruction produced by a macro expansion back to the
  invocation line. Without an assembler listing, the view cannot tell which
  line inside the macro body is currently executing; it shows the definition
  and the invocation that is responsible for the current PC.

### source

The source pane shows up to five lines on each side of the current line:

```text
=> 60      SET_CLOCK_8Mhz
   61
   62      ENABLE_SYSTICK
```

Pygments is used when it is importable from the GDB Python environment.
Assembly uses the GAS lexer, C/C++ headers use the C lexer, and the terminal
formatter uses the `monokai` style. Without Pygments the pane is plain text.
The raw line text is kept separately from the coloured text so macro detection
still works when colours are enabled.

Pygments is installed for the WCH GDB with:

```bash
pip3 install --no-deps --target ~/.local/opt/wch-toolchain/share/gdb/python \
    'pygments==2.19.2'
```

A toolchain reinstall removes it; rerun the command after upgrading the WCH
toolchain.

## Safety and remote I/O

The view is an observer: it must not change the program being debugged.

- **MMIO is not dereferenced by default.** APB (`0x40000000-0x40030000`) and
  core-peripheral (`0xE0000000-0xE0010000`) addresses are skipped. Reading a
  peripheral register can clear bits, advance a FIFO, or trigger another side
  effect. Use `ctx mmio on` only when you understand the peripheral.
- **Flash and SRAM are safe to preview.** Code addresses are read for opcode
  bytes and pointer values, but never treated as strings.
- **Unreadable words are silent.** A failed read produces `??` or omits the
  preview; it never aborts the stop hook.
- **One transaction per section type.** Registers come from a single
  `info registers`; the stack window and the disassembly window are each read
  once. Symbol lookups are local ELF operations.
- `ctx deref off` removes all pointer/string previews, leaving only the raw
  register and stack values. This is the fastest mode and the safest mode on a
  peripheral-heavy target.

The memory map combines the ELF's `ALLOC` sections with the known CH32V003
windows:

| Range | Purpose |
| --- | --- |
| `0x00000000-0x00004000` | 16 kB flash |
| `0x08000000-0x08004000` | flash alias |
| `0x20000000-0x20000800` | 2 kB SRAM (map end is extended by 4 bytes for the reset `$sp`) |
| `0x40000000-0x40030000` | APB peripherals |
| `0xE0000000-0xE0010000` | core peripherals, PFIC, SysTick |
| `0x1FFFF704-0x1FFFF708` | ESIG |
| `0x1FFFF7E0-0x1FFFF7F4` | INFO |
| `0x1FFFF800-0x1FFFF80C` | option bytes |

## Troubleshooting

**No output after connecting.** The target may not be stopped, or `$pc` is not
available. Run `ctx` manually. If GDB reports that `ctx` is unknown, source
`~/.config/nvim/ch32ctx.gdb`; check that `readlink /proc/$PPID/exe` points at
the WCH toolchain.

**No colours.** Check `python import pygments` inside GDB and set
`NO_COLOR=` (unset it). The view also honours `NO_COLOR`; an empty value still
disables colours.

**No macro pane.** The current line may not be a macro invocation, or the
definition may be outside `src/**/*.s`/`*.inc`. Add the file to the source tree
or extend `MacroIndex` for a different layout.

**Everything is slow.** Run `ctx deref off`, or select fewer panes (`ctx
registers code source`). A remote minichlink connection is the bottleneck, not
the formatter.

**GEF and ch32ctx both print.** GEF is optional and no longer auto-loaded.
Start it deliberately with `chef`; use `ctx off` if you only want GEF's view.

## Development

The package is split so the display logic is testable without GDB:

```text
ch32ctx/
  model.py       immutable data types
  formatting.py  pure text renderers
  window.py      mixed-length disassembly window
  source.py      source slicing and optional Pygments
  macros.py      .macro index and invocation lookup
  render.py      pane composition (GDB-free)
  target.py      the only module that imports gdb
  context.py     the ctx command and stop hook
```

Run from the repository root:

```bash
python3 -m unittest discover -s tests/ch32ctx -v
python3.8 -m unittest discover -s tests/ch32ctx -t .   # GDB's interpreter
uvx ruff format --check ch32ctx tests/ch32ctx
uvx ruff check --target-version py38 ch32ctx tests/ch32ctx
uvx mypy --python-version 3.8 --ignore-missing-imports \
    ch32ctx tests/ch32ctx/test_target.py
```

The integration test in `tests/ch32ctx/test_integration.py` skips cleanly when
`riscv-wch-elf-gdb` is not installed.

## Limitations

- RV32EC only: the register list is fixed to the sixteen WCH core registers.
- The memory map is specific to the CH32V003 (16 kB flash, 2 kB SRAM).
- Exact macro-body line tracking needs an assembler listing; the current view
  shows the definition and the invocation.
- The loader check is Linux-specific (`/proc/$PPID/exe`), matching the WSL and
  Fedora setup this repository targets.
