; extends

; GNU asm / RISC-V32EC token classes.  The generic asm parser already
; distinguishes these node types; map them onto standard capture names so the
; active colorscheme can color instructions, registers, labels, directives,
; numbers, and comments consistently.
(instruction kind: (word) @keyword)
(reg (word) @variable.builtin)
(label (ident) @label)
(meta kind: (meta_ident) @keyword.directive)
(int) @number
(line_comment) @comment
