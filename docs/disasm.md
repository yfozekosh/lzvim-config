# Disassembly view

A local plugin (`lua/disasm/`, commands in `plugin/disasm.lua`) that opens a
vertical split with the real disassembly of the project's ELF and highlights
every instruction the ELF's debug line table attributes to the source line
under the cursor.

## Commands

- `:DisasmOpen [elf]` — open (or refresh) the split. With no path the ELF is
  auto-detected under `out/`, `build/`, or the project root; if several exist,
  you are prompted.
- `:DisasmClose` — close the split.
- `:DisasmToggle [elf]` — open or close.
- `:DisasmRefresh` — rerun objdump and rebuild the line index.
- In the asm split: `q` closes, `r` refreshes, `K` shows RISC-V hover docs,
  `L` cycles the cycle view between off, both latencies, L1 only, and L0 only,
  and `S` toggles instruction sizes next to addresses (`15e(4):`).

## Configuration

Set `vim.g.disasm` before the plugin loads (e.g. in `lua/config/options.lua`):

```lua
vim.g.disasm = {
  objdump = "riscv-none-elf-objdump", -- string or argv table
  elf = nil,                          -- path or function returning one
  args = { "-d", "-l", "-C", "--no-show-raw-insn" },
  auto_scroll = true,
  highlight = "Visual",               -- highlight group linked to DisasmMatch
  winbar = true,
  auto_refresh = true,               -- refresh automatically when the ELF changes
  cycles = true,                     -- master switch for cycle annotations
  cycle_view = "off",                -- "off", "both", "l1", or "l0"
  show_sizes = false,                -- S toggles (4)/(2) next to addresses
  flash_start = 0x00000000,
  flash_end = 0x00004000,            -- end-exclusive; CH32V003 has 16 KiB flash
  data_is_flash = false,             -- set true if code loads constants from flash
}
```

## Instruction sizes

`S` toggles the encoded size of each instruction next to its address, e.g.
`15e(4):` for a 32-bit instruction or `152(2):` for a 16-bit one. The size is
inserted as virtual text, so the disassembly and source mapping are unchanged.
Sizes work even when cycle annotations are off; they come from the raw-byte
objdump pass, with the next-address difference as a fallback. A 16-bit NOP is
displayed as `c.nop`; a 32-bit NOP remains `nop`.

## How the mapping works

The plugin runs `objdump -d -l -C` and parses the `path:line` markers it
emits. Those markers come from the ELF's `.debug_line` section, so the
mapping reflects the actual compiled and linked code, including `-Os`
reordering. A source line can own several disjoint instruction ranges; all
of them are highlighted. An unmarked function (for example one built without
`-g`) is left unmapped rather than mis-attributed.

Marker paths are resolved against the opened project: the ELF's project root,
the ELF directory, its parent, and the current directory. Absolute paths
recorded at build time are not trusted blindly — the longest existing suffix
of the path is looked up under those roots first, so a stale or foreign path
such as `/old/place/src/main.c` maps to `<root>/src/main.c` even when the old
path still exists. The recorded absolute path is only a fallback.

## Cycle totals

Each basic block gets a cycle total appended as virtual text. This follows
the CH32V003 simulator's timing model in
`~/Projects/ch32v003-sim/doc/emulation-architecture.md`, not a per-instruction
cold-start estimate:

- **Latency 0:** base 1 cycle per instruction; load/store +1; taken
  branch/jump/return +2; a 32-bit flash instruction at `4k+2` +1 unless the
  preceding 16-bit instruction filled the first half of that word. When the
  +1 applies, the L0 annotation includes `(+1 misaligned)` so the penalty is
  visible in the total.
- **Latency 1:** flash fetch costs 2 cycles per executed 4-byte chunk, and the
  fetch phase continues across fallthrough edges; a taken transfer costs +4,
  or +2 for an aligned 32-bit conditional (and one first-in-block boundary
  case); load/store +2 when it straddles a chunk or crosses none, plus +2 for
  a flash data access. SRAM code is not fetch-limited: base 1, load/store +1,
  taken transfer +2.

Cycle annotations are off by default, so a freshly opened split stays clean.
`L` cycles through off, both latencies, L1-only, and L0-only; the winbar shows
no suffix when off, then `[L0+1]`, `[L1]`, and `[L0]`. The ELF does not record
the flash latency the firmware selected at runtime, so showing both avoids
having to guess it.

When both latencies are shown, the annotation forms are:

- `; L0 2 · L1 6 cyc` — one block total at each latency.
- `; L0 4/2 · L1 6/2 cyc` — conditional branch block; each pair is
  taken/fallthrough.
- `; L0 4 or 6 · L1 6 or 8 cyc` — the block is reachable with more than one
  fetch state.

These alternatives are discrete, not a continuous range. For example, a lone
`ret` at latency 1 is either 4 or 6 cycles depending on how it was entered; it
never takes 5. When a single latency is selected, block totals are prefixed
with that latency and use the compact `taken/fallthrough` form:
`; L0 6 cyc`, `; L0 3/1 cyc`, `; L1 6/4 cyc`.

When latency 0 is visible, each instruction line also shows its own L0 cost.
At a multi-instruction block start the line cost and block totals are shown
together:

- `; L0 1 · block 4/2 · L1 6/4 cyc` — the first instruction costs 1
  cycle, while the whole block costs 4 taken / 2 fallthrough at L0 and
  6 taken / 4 fallthrough at L1.
- `; L0 1 · block 4/2 cyc` — the same block when only L0 is selected.
- `; L0 3/1 cyc` — a non-start line, such as a conditional terminator,
  costs 3 cycles when taken and 1 when falling through.
- A one-instruction block shows only the block total, because its line cost
  and block total are the same: `; L0 3/1 cyc` or
  `; L0 3/1 · L1 4/2 cyc`.

An L0 total that includes the `4k+2` flash penalty is marked
`(+1 misaligned)`, for example `; L0 2 (+1 misaligned) cyc` or
`; L0 1 (+1 misaligned) · block 2 cyc`. The marker is absent when the
preceding 16-bit instruction filled the first half of the same word, because
that case takes the waiver.

L1 also shows per-line costs, in the same compact form (`; L1 0 cyc`,
`; L1 2 cyc`, `; L1 6/2 cyc`). The 2-cycle fetch charge is attributed to the
instruction that crosses a 4-byte chunk boundary; an instruction wholly inside
the current chunk shows a 0 fetch component. The per-line split is a model
allocation, not a hardware-visible event, so the block total remains the
authoritative number. L1 line costs also include data-access extras and the
taken/fallthrough redirect overhead on the terminator line.

Every annotated block gets `· block start: <reason>` on its first instruction
line, e.g. `; L0 1 · block 4/2 cyc · block start: target of j 8`, so the
boundary and its cause are explicit even when the line also carries a per-line
L0 cost. Reasons include a function entry, a branch/jump target, fallthrough
after a control transfer, or an address gap.

A multi-instruction block also gets `· end block: <reason>` on its last
instruction line, e.g. `; L0 3/1 cyc · end block: conditional bgtz`.
Reasons include a conditional branch, a jump, an indirect transfer/return,
the next instruction being a branch target, or a function/section end.
One-instruction blocks end where they start, so both reasons appear on the
same row instead of adding a separate end marker.

A `jal`, `call`, or `jalr` call that writes the standard link register `ra`
creates both the callee edge and a return edge to the next instruction, so
post-call code is annotated even though the return target is not statically
known. The return edge starts a fresh fetch and assumes the callee returns;
plain jumps (`j`, `tail`) and `jalr` with a non-`ra` link register do not get
one.

Start reasons are highlighted green (`DiagnosticOk`), end reasons yellow
(`DiagnosticWarn`), and `(+1 misaligned)` red (`DiagnosticError`). Cycle
virtual text uses `hl_mode = "combine"`, so when a source line is highlighted,
its annotation is drawn with the same combined highlight instead of staying a
separate, unhighlighted color.

A block total is the marginal cost of executing that block. If a block falls
through, a partially used final fetch chunk is charged to the next block; a
tiny block that does not end in a transfer can therefore show `0 cyc`.
Data-only blocks (vector/jump tables) contain no instructions, so they are
not annotated; every real instruction gets an annotation. A block with no
statically known entry still gets a cold cost labeled `(no known entry)`,
not a `~` marker.
Blocks consisting of `.word`, `.short`, or `.insn` directives are counted as
fetch bytes when they are reachable, because such directives in `.text` can be
executable instructions.

Indirect control flow (`jalr`, `ret`) ends a block but does not reveal its
target. A following block with no other predecessor now gets a cold fallback
annotation labeled `(no known entry)`; this is not a real control-flow edge.
Unreachable padding gets the same label. The static
model also cannot know whether a load/store address is flash, so
`data_is_flash` applies globally; leave it `false` for ordinary RAM/MMIO data.
Interrupt entry, `mret`, WFI wake, and polled-timer timing are outside this
static block model.

## Limitations

- The ELF must be rebuilt after editing source; the plugin does not run
  `make`. The split auto-refreshes when the ELF's mtime changes (polling
  every second); `:DisasmRefresh` still reruns objdump manually.
  Set `auto_refresh = false` to get a one-time warning instead.
- Source files newer than the ELF produce a one-time warning; the mapping
  is still shown.
- Unsaved source buffers may have shifted line numbers; a warning is shown
  and `[modified]` appears in the winbar.
- Only GNU objdump-style output with `-l` is supported.
- Reverse sync (asm cursor to source) is not implemented in v1.

## Example (`t1`)

```vim
cd /home/yfozekosh/Projects/riskv_asm/t1
nvim src/test.c
" :DisasmOpen   " auto-detects out/firmware.elf
```

Moving over line 13 highlights both the `lui`/`lw` group and the
`lw a0,0(a5)` / `jal delay` group; the split scrolls to the first one.