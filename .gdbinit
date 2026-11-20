# ==========================================
# 1. Terminal Styling & Display Formatting
# ==========================================
set pagination off
set confirm off
set verbose off

# Fancy colored prompt indicating our target connection
set prompt (gdb) \[\033[1;36m\][MCU:3333]\[\033[0m\] 

# Enable modern ANSI syntax styling (GDB 8.3+)
set style enabled on

# Print hex values in 0x00 format cleanly
set output-radix 16
set input-radix 16

# ==========================================
# 2. Connection Settings (extended-remote)
# ==========================================
set remotetimeout 10
set remote hardware-breakpoint-limit 4
set remote hardware-watchpoint-limit 2

# Connection is deferred until the ELF has been loaded.  For RV32E parts
# (e.g. CH32V003) minichlink reports only 16 registers, and GDB only
# switches to that layout after it has read the ELF's architecture, so
# attaching here (before the file is loaded) fails with
# "Truncated register 8 in remote 'g' packet".
define connect
    # Reconnect safely: drop a stale connection (if any) before attaching.
    if !$_isvoid($_gdb_connected)
        if $_gdb_connected == 1
            set $_gdb_connected = 0
            disconnect
        end
    end
    target extended-remote localhost:3333
    monitor reset halt
    maintenance flush register-cache
    set $_gdb_connected = 1
end
document connect
    Attach/re-attach to the GDB server on localhost:3333 (minichlink/OpenOCD) and halt.
end

# `monitor` commands can change the target without notifying GDB. Refresh the
# register/frame cache afterward so PC and disassembly reflect the new state.
define hookpost-monitor
    maintenance flush register-cache
end

# ==========================================
# 3. Microcontroller Debug Utilities
# ==========================================

# AUTO-DISASSEMBLE NEXT LINE:
# Shows the exact instruction pointer & upcoming assembly line every time GDB halts/steps
set disassemble-next-line on

# Auto-load symbols and halt at reset (deferred to `connect`)

# ==========================================
# 4. Custom Helper Shortcuts
# ==========================================

# --- Shortcut: 'd' for instant disassembly around PC ---
define d
    disassemble $pc, $pc+0x20
end
document d
    Quickly dumps the next 0x20 bytes of disassembly starting from the current PC.
end

# --- Shortcut: 'dc' to disassemble the whole current function ---
define dc
    disassemble $pc
end
document dc
    Disassembles the whole current function, including instructions before PC.
end

# --- Shortcut: 'dmain' to disassemble main ---
define dmain
    disassemble main
end
document dmain
    Disassembles the full main function.
end

# --- Shortcut: 'vec' to inspect bare-metal Vector Table (0x0 to 0x20) ---
define vec
    echo \n--- Flash Reset Vector Table (0x0 - 0x20) ---\n
    x/8xw 0x00000000
end
document vec
    Dumps the first 8 32-bit words starting at memory address 0x0 (Interrupt Vector Table).
end

# --- Shortcut: 'reset' to reset, halt, and refresh GDB's register cache ---
define reset
    monitor reset halt
    maintenance flush register-cache
end
document reset
    Resets and halts the target, then refreshes GDB's cached registers.
end

# --- Shortcut: 'reload' to re-flash and halt ---
define reload
    echo \n[GDB] Resetting MCU and reloading code...\n
    monitor reset halt
    load
    monitor reset halt
    maintenance flush register-cache
    # Rebuild the GEF memory map from the freshly loaded ELF. Do not start
    # GEF here if it was not already loaded in this session.
    python import __main__, gdb; hasattr(__main__, "gef") and gdb.execute("chef")
    echo [GDB] Flash write complete. Ready at entry point.\n
end
document reload
    Resets the chip via SWIO/SWD, re-flashes the target binary, and halts at vector start.
end

# Auto-connect when this GDB is started from the mtrx_asm project root.
# (The ELF must be loaded before attaching; see the `connect` command.)
shell test -f ./out/firmware.elf
if $_shell_exitcode == 0
    file ./out/firmware.elf
    connect
end

# --- Shortcut: 'ui' to launch TUI split view ---
define ui
    layout split
    focus cmd
end
document ui
    Toggles TUI mode with source/assembly windows split side-by-side.
end

# --- Shortcut: 'r' for register overview ---
define r
    info registers
end
document r
    Short for info registers (hex only).
end

# --- Shortcut: 'rd' for register overview in decimal ---
# RV32EC (CH32V003) exposes only x0-x15 plus pc, whose GDB names are:
#   zero ra sp gp tp t0 t1 t2 fp s1 a0 a1 a2 a3 a4 a5 pc
# (x8 is 'fp', there is no 's0').  `info registers` always prints hex;
# printf ignores output-radix, so this prints decimal with hex alongside.
define rd
    printf "%-4s %10s  %-10s\n", "reg", "dec", "hex"
    printf "%-4s %10u  0x%08x\n", "pc", (unsigned int)$pc, (unsigned int)$pc
    printf "%-4s %10u  0x%08x\n", "ra", (unsigned int)$ra, (unsigned int)$ra
    printf "%-4s %10u  0x%08x\n", "sp", (unsigned int)$sp, (unsigned int)$sp
    printf "%-4s %10u  0x%08x\n", "gp", (unsigned int)$gp, (unsigned int)$gp
    printf "%-4s %10u  0x%08x\n", "tp", (unsigned int)$tp, (unsigned int)$tp
    printf "%-4s %10u  0x%08x\n", "t0", (unsigned int)$t0, (unsigned int)$t0
    printf "%-4s %10u  0x%08x\n", "t1", (unsigned int)$t1, (unsigned int)$t1
    printf "%-4s %10u  0x%08x\n", "t2", (unsigned int)$t2, (unsigned int)$t2
    printf "%-4s %10u  0x%08x\n", "fp", (unsigned int)$fp, (unsigned int)$fp
    printf "%-4s %10u  0x%08x\n", "s1", (unsigned int)$s1, (unsigned int)$s1
    printf "%-4s %10u  0x%08x\n", "a0", (unsigned int)$a0, (unsigned int)$a0
    printf "%-4s %10u  0x%08x\n", "a1", (unsigned int)$a1, (unsigned int)$a1
    printf "%-4s %10u  0x%08x\n", "a2", (unsigned int)$a2, (unsigned int)$a2
    printf "%-4s %10u  0x%08x\n", "a3", (unsigned int)$a3, (unsigned int)$a3
    printf "%-4s %10u  0x%08x\n", "a4", (unsigned int)$a4, (unsigned int)$a4
    printf "%-4s %10u  0x%08x\n", "a5", (unsigned int)$a5, (unsigned int)$a5
    systick
end
document rd
    Prints the RV32EC integer registers in decimal (hex alongside for reference),
    followed by the SysTick registers.
end

# --- Shortcut: 'systick' for the QingKe SysTick block (0xE000F000) ---
# CH32V003 layout: CTLR +0x00, SR +0x04, CNT +0x08 (32-bit), CMP +0x10.
# CTLR: STE=1 STIE=2 STCLK=4 STRE=8 SWIE=0x80000000.  SR: CNTIF=1.
# Firmware usually reads the counter through SysTick->CNT, so we do the same.
define systick
    set $stk_ctlr = *(unsigned int *)0xE000F000
    set $stk_sr   = *(unsigned int *)0xE000F004
    set $stk_cnt  = *(unsigned int *)0xE000F008
    set $stk_cmp  = *(unsigned int *)0xE000F010
    printf "CTLR 0x%08x %10u  STE=%u STIE=%u STCLK=%u STRE=%u SWIE=%u\n", $stk_ctlr, $stk_ctlr, ($stk_ctlr&1)!=0, ($stk_ctlr&2)!=0, ($stk_ctlr&4)!=0, ($stk_ctlr&8)!=0, ($stk_ctlr&0x80000000)!=0
    printf "SR   0x%08x %10u  CNTIF=%u\n", $stk_sr, $stk_sr, ($stk_sr&1)!=0
    printf "CNT  0x%08x %10u\n", $stk_cnt, $stk_cnt
    printf "CMP  0x%08x %10u\n", $stk_cmp, $stk_cmp
end
document systick
    Prints the CH32V003 SysTick registers (0xE000F000) in decimal and hex,
    with the CTLR/SR bits decoded.
end

# ==========================================
# 5. GEF (optional, on demand)
# ==========================================
# GEF is userland-oriented, but its RISCV arch layer and context view are
# useful on the MCU. It is no longer loaded by default; `chef` starts it when
# wanted, while the tracked CH32V003 context view lives in section 7. This is the yfozekosh/gef fork
# (branch ch32v003-rv32ec, based on 2024.06: 2025.01+ requires Python >= 3.10
# and this GDB embeds 3.8), symlinked from ~/Projects/gef. PYTHONHOME must be
# dropped first, otherwise GEF's internal `python3` probe inherits this GDB's
# Python home and fails to find the system stdlib. The companion script adds a
# bare-metal memory map (GEF needs one for `registers`/`dereference`), trims the
# register set to RV32E, syntax-highlights the source pane with Pygments, and
# applies the embedded context profile.
# After loading, GEF replaces `gef` with its own help command.
define gef
    python import os; os.environ.pop("PYTHONHOME", None)
    source ~/.local/share/gef/gef.py
    python import os, runpy; runpy.run_path(os.path.expanduser("~/.local/share/gef/gef_riscv.py"))
end
document gef
    Load GEF (GDB Enhanced Features) into this session.
end

# Enter the GEF environment with one command. If GEF is already loaded this
# only re-applies the companion patch (useful after `reload`).
define chef
    python
import os, runpy, __main__
if not hasattr(__main__, "gef"):
    os.environ.pop("PYTHONHOME", None)
    gdb.execute("source ~/.local/share/gef/gef.py")
runpy.run_path(os.path.expanduser("~/.local/share/gef/gef_riscv.py"))
end
end
document chef
    Load GEF if needed, then apply the CH32V003 patch (memory map, RV32E
    registers, source colors, embedded context profile).
end

# ==========================================
# 6. Machine-local additions (not tracked)
# ==========================================
# Keep host-specific defaults out of the shared configuration. The file is
# optional; this hook is harmless when absent.
shell test -f ~/.gdbinit.local
if $_shell_exitcode == 0
    source ~/.gdbinit.local
end

# ==========================================
# 7. CH32V003 context view (WCH GDB only)
# ==========================================
# The WCH toolchain GDB embeds Python 3.8; other GDBs on this machine either
# have no Python (xPack) or target a different workflow. The executable check
# keeps the view out of those sessions without changing the shared config.
shell readlink /proc/$PPID/exe | grep -q wch-toolchain
if $_shell_exitcode == 0
    source ~/.config/nvim/ch32ctx.gdb
    # The auto-connect above already stopped the target before this hook was
    # installed, so print the first context explicitly.
    if !$_isvoid($_gdb_connected)
        if $_gdb_connected == 1
            ctx
        end
    end
end
