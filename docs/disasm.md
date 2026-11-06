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
- In the asm split: `q` closes, `r` refreshes, `K` shows RISC-V hover docs.

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
}
```

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