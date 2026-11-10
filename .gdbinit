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
    set $_gdb_connected = 1
end
document connect
    Attach/re-attach to the GDB server on localhost:3333 (minichlink/OpenOCD) and halt.
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

# --- Shortcut: 'reload' to re-flash and halt ---
define reload
    echo \n[GDB] Resetting MCU and reloading code...\n
    monitor reset halt
    load
    monitor reset halt
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
    Short for info registers.
end
