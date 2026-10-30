; extends
;
; Extra highlights for GNU assembler / RISC-V assembly.
;
; tree-sitter-asm already highlights generic GAS syntax (instructions,
; registers, labels, directives). These rules only refine it:
;
; * GAS directives (`.section`, `.globl`, `.macro`, ...) get their own group
;   instead of sharing @function.builtin with instruction mnemonics.
; * RISC-V CSRs are ordinary `reg` operands to the grammar, so they would
;   otherwise look identical to general-purpose registers such as `a0`/`t0`.

; GAS directives (parsed as `meta`)
(meta kind: (_) @keyword)

; RISC-V control and status registers
((reg) @constant.builtin
  (#any-of? @constant.builtin
    ; floating-point CSRs
    "fflags" "frm" "fcsr"
    ; counters
    "cycle" "time" "instret" "cycleh" "timeh" "instreth"
    ; machine-mode CSRs
    "mstatus" "mstatush" "misa" "medeleg" "mideleg" "mie" "mtvec"
    "mcounteren" "mcountinhibit" "mscratch" "mepc" "mcause" "mtval" "mip"
    "menvcfg" "menvcfgh" "mseccfg" "mseccfgh"
    "mhartid" "mvendorid" "marchid" "mimpid" "mconfigptr"
    "mstateen0" "mstateen1" "mstateen2" "mstateen3"
    "mcontext" "mrmcfg"
    ; supervisor-mode CSRs
    "sstatus" "sie" "stvec" "scounteren" "sscratch" "sepc" "scause" "stval"
    "sip" "satp" "senvcfg" "sedeleg" "sideleg" "stimecmp" "stimecmph"
    "scountovf" "sstateen0" "sstateen1" "sstateen2" "sstateen3"
    "scontext" "srmcfg"
    ; hypervisor CSRs
    "hstatus" "hedeleg" "hideleg" "hie" "hcounteren" "hgeie" "htval" "hip"
    "hvip" "htinst" "hgatp" "hgeip" "henvcfg" "henvcfgh" "hcontext"
    "htimedelta" "htimedeltah" "hvien" "hviph" "hviprio1" "hviprio2"
    "hstateen0" "hstateen1" "hstateen2" "hstateen3"
    ; vector CSRs
    "vstart" "vxsat" "vxrm" "vcsr" "vtype" "vl" "vlenb" "vstateen"
    ; pointer masking / jump-table / seed CSRs
    "jvt" "seed"))

; Counter and PMP CSRs have numbered names. (Lua patterns: `-` is the
; optional/repetition operator, there is no `?` or `|` alternation.)
((reg) @constant.builtin
  (#lua-match? @constant.builtin "^m-hpmcounter%d+h-$"))
((reg) @constant.builtin
  (#lua-match? @constant.builtin "^mhpmevent%d+$"))
((reg) @constant.builtin
  (#lua-match? @constant.builtin "^pmpcfg%d+$"))
((reg) @constant.builtin
  (#lua-match? @constant.builtin "^pmpaddr%d+$"))
