--- RISC-V assembly extras that upstream asm-lsp does not provide.
---
--- asm-lsp's RISC-V database only contains base-ISA mnemonics (upstream
--- issue #261), so `la`, `li`, `mv`, `ret`, ABI register names (`a0`, `t0`,
--- ...) and CSRs have no hover/completion. This module supplies the common
--- scalar ones. It is used by:
---   * the `K` hover wrapper in `lua/plugins/asm.lua`
---   * the `riscv_asm` blink.cmp source (`module = "riscv_asm"`)
local M = {}

--- @alias RiscvAsmPseudo { [1]: string, [2]: string, [3]: string }
--- @alias RiscvAsmRegister { [1]: string, [2]: string, [3]: string, [4]: string }
--- @alias RiscvAsmCsr { [1]: string, [2]: integer, [3]: string }

--- @type RiscvAsmPseudo[]
local pseudos = {
  {
    "la",
    "auipc rd, %pcrel_hi(symbol)\naddi rd, rd, %pcrel_lo(symbol)",
    "Load address (non-PIC; with `.option pic` it uses the GOT)",
  },
  { "lla", "auipc rd, %pcrel_hi(symbol)\naddi rd, rd, %pcrel_lo(symbol)", "Load local address" },
  { "lga", "auipc rd, %got_pcrel_hi(symbol)\nlw/ld rd, %pcrel_lo(symbol)(rd)", "Load global address through the GOT" },
  { "nop", "addi x0, x0, 0", "No operation" },
  { "li", "lui + addi/addiw (optimal sequence)", "Load immediate" },
  { "mv", "addi rd, rs, 0", "Copy register" },
  { "not", "xori rd, rs, -1", "One's complement" },
  { "neg", "sub rd, x0, rs", "Two's complement" },
  { "negw", "subw rd, x0, rs", "Two's complement word (RV64)" },
  { "sext.b", "slli rd, rs, XLEN-8\nsrai rd, rd, XLEN-8", "Sign-extend byte (single instruction with Zbb)" },
  { "sext.h", "slli rd, rs, XLEN-16\nsrai rd, rd, XLEN-16", "Sign-extend halfword (single instruction with Zbb)" },
  { "sext.w", "addiw rd, rs, 0", "Sign-extend word (RV64)" },
  { "zext.b", "andi rd, rs, 255", "Zero-extend byte" },
  { "zext.h", "slli rd, rs, XLEN-16\nsrli rd, rd, XLEN-16", "Zero-extend halfword (single instruction with Zbb)" },
  { "zext.w", "slli rd, rs, XLEN-32\nsrli rd, rd, XLEN-32", "Zero-extend word (RV64; `add.uw` with Zba)" },
  { "seqz", "sltiu rd, rs, 1", "Set if equal to zero" },
  { "snez", "sltu rd, x0, rs", "Set if not equal to zero" },
  { "sltz", "slt rd, rs, x0", "Set if less than zero" },
  { "sgtz", "slt rd, x0, rs", "Set if greater than zero" },
  { "sgt", "slt rd, rt, rs", "Set if greater than" },
  { "sgtu", "sltu rd, rt, rs", "Set if greater than, unsigned" },
  { "beqz", "beq rs, x0, offset", "Branch if equal to zero" },
  { "bnez", "bne rs, x0, offset", "Branch if not equal to zero" },
  { "blez", "bge x0, rs, offset", "Branch if less than or equal to zero" },
  { "bgez", "bge rs, x0, offset", "Branch if greater than or equal to zero" },
  { "bltz", "blt rs, x0, offset", "Branch if less than zero" },
  { "bgtz", "blt x0, rs, offset", "Branch if greater than zero" },
  { "bgt", "blt rt, rs, offset", "Branch if greater than" },
  { "ble", "bge rt, rs, offset", "Branch if less than or equal to" },
  { "bgtu", "bltu rt, rs, offset", "Branch if greater than, unsigned" },
  { "bleu", "bgeu rt, rs, offset", "Branch if less than or equal to, unsigned" },
  { "j", "jal x0, offset", "Jump" },
  { "jump", "auipc rt, %pcrel_hi(offset)\njalr x0, %pcrel_lo(offset)(rt)", "Jump to a far-away label" },
  { "jr", "jalr x0, 0(rs)", "Jump register" },
  { "ret", "jalr x0, 0(ra)", "Return from subroutine" },
  {
    "call",
    "auipc ra, %pcrel_hi(symbol)\njalr ra, %pcrel_lo(symbol)(ra)",
    "Call a far-away subroutine (`call rd, symbol` saves the return address in `rd`)",
  },
  {
    "tail",
    "auipc t1, %pcrel_hi(symbol)\njalr x0, %pcrel_lo(symbol)(t1)",
    "Tail-call a far-away subroutine (`tail symbol, rt` uses `rt` as scratch)",
  },
  { "pause", "fence w, 0", "PAUSE hint (Zihintpause)" },
  { "csrr", "csrrs rd, csr, x0", "Read CSR" },
  { "csrw", "csrrw x0, csr, rs", "Write CSR" },
  { "csrs", "csrrs x0, csr, rs", "Set bits in CSR" },
  { "csrc", "csrrc x0, csr, rs", "Clear bits in CSR" },
  { "csrwi", "csrrwi x0, csr, imm", "Write CSR, immediate" },
  { "csrsi", "csrrsi x0, csr, imm", "Set bits in CSR, immediate" },
  { "csrci", "csrrci x0, csr, imm", "Clear bits in CSR, immediate" },
  { "rdcycle", "csrrs rd, cycle, x0", "Read cycle counter" },
  { "rdcycleh", "csrrs rd, cycleh, x0", "Read upper 32 bits of cycle counter (RV32)" },
  { "rdtime", "csrrs rd, time, x0", "Read real-time clock" },
  { "rdtimeh", "csrrs rd, timeh, x0", "Read upper 32 bits of real-time clock (RV32)" },
  { "rdinstret", "csrrs rd, instret, x0", "Read instructions-retired counter" },
  { "rdinstreth", "csrrs rd, instreth, x0", "Read upper 32 bits of instructions-retired counter (RV32)" },
  { "frcsr", "csrrs rd, fcsr, x0", "Read FP control/status register" },
  {
    "fscsr",
    "csrrw rd, fcsr, rs",
    "Swap/write FP control/status register (`fscsr rs` writes, discarding the old value)",
  },
  { "frrm", "csrrs rd, frm, x0", "Read FP rounding mode" },
  { "fsrm", "csrrw rd, frm, rs", "Swap/write FP rounding mode (`fsrm rs` writes, discarding the old value)" },
  { "fsrmi", "csrrwi rd, frm, imm", "Swap/write FP rounding mode, immediate" },
  { "frflags", "csrrs rd, fflags, x0", "Read FP exception flags" },
  {
    "fsflags",
    "csrrw rd, fflags, rs",
    "Swap/write FP exception flags (`fsflags rs` writes, discarding the old value)",
  },
  { "fsflagsi", "csrrwi rd, fflags, imm", "Swap/write FP exception flags, immediate" },
}

-- Floating-point pseudos for each supported precision.
local precisions = { h = "half", s = "single", d = "double", q = "quad" }
for fmt, name in pairs(precisions) do
  local fp = {
    { "fmv." .. fmt, "fsgnj." .. fmt .. " frd, frs, frs", "Copy " .. name .. "-precision register" },
    {
      "fabs." .. fmt,
      "fsgnjx." .. fmt .. " frd, frs, frs",
      name:gsub("^%l", string.upper) .. "-precision absolute value",
    },
    { "fneg." .. fmt, "fsgnjn." .. fmt .. " frd, frs, frs", name:gsub("^%l", string.upper) .. "-precision negate" },
    { "fgt." .. fmt, "flt." .. fmt .. " rd, frt, frs", name:gsub("^%l", string.upper) .. "-precision greater than" },
    {
      "fge." .. fmt,
      "fle." .. fmt .. " rd, frt, frs",
      name:gsub("^%l", string.upper) .. "-precision greater or equal",
    },
  }
  for _, p in ipairs(fp) do
    pseudos[#pseudos + 1] = p
  end
end

--- @type RiscvAsmRegister[]
local gprs = {
  { "zero", "x0", "Hard-wired zero", "n/a" },
  { "ra", "x1", "Return address", "no" },
  { "sp", "x2", "Stack pointer", "yes" },
  { "gp", "x3", "Global pointer", "n/a" },
  { "tp", "x4", "Thread pointer", "n/a" },
  { "t0", "x5", "Temporary register 0", "no" },
  { "t1", "x6", "Temporary register 1", "no" },
  { "t2", "x7", "Temporary register 2", "no" },
  { "s0", "x8", "Saved register 0 (alias `fp`)", "yes" },
  { "fp", "x8", "Frame pointer (alias of `s0`)", "yes" },
  { "s1", "x9", "Saved register 1", "yes" },
  { "a0", "x10", "Argument 0 / return value", "no" },
  { "a1", "x11", "Argument 1 / return value", "no" },
  { "a2", "x12", "Argument 2", "no" },
  { "a3", "x13", "Argument 3", "no" },
  { "a4", "x14", "Argument 4", "no" },
  { "a5", "x15", "Argument 5", "no" },
  { "a6", "x16", "Argument 6", "no" },
  { "a7", "x17", "Argument 7", "no" },
  { "s2", "x18", "Saved register 2", "yes" },
  { "s3", "x19", "Saved register 3", "yes" },
  { "s4", "x20", "Saved register 4", "yes" },
  { "s5", "x21", "Saved register 5", "yes" },
  { "s6", "x22", "Saved register 6", "yes" },
  { "s7", "x23", "Saved register 7", "yes" },
  { "s8", "x24", "Saved register 8", "yes" },
  { "s9", "x25", "Saved register 9", "yes" },
  { "s10", "x26", "Saved register 10", "yes" },
  { "s11", "x27", "Saved register 11", "yes" },
  { "t3", "x28", "Temporary register 3", "no" },
  { "t4", "x29", "Temporary register 4", "no" },
  { "t5", "x30", "Temporary register 5", "no" },
  { "t6", "x31", "Temporary register 6", "no" },
}

local fprs = {}
local function add_fpr(label, index, use, preserved)
  fprs[#fprs + 1] = { label, "f" .. index, use, preserved }
end
for i = 0, 7 do
  add_fpr("ft" .. i, i, "FP temporary register " .. i, "no")
end
add_fpr("fs0", 8, "FP saved register 0", "yes")
add_fpr("fs1", 9, "FP saved register 1", "yes")
for i = 0, 7 do
  add_fpr("fa" .. i, 10 + i, "FP argument " .. i .. (i < 2 and " / return value" or ""), "no")
end
for i = 2, 11 do
  add_fpr("fs" .. i, 18 + i - 2, "FP saved register " .. i, "yes")
end
for i = 8, 11 do
  add_fpr("ft" .. i, 28 + i - 8, "FP temporary register " .. i, "no")
end

--- @type RiscvAsmCsr[]
local csrs = {
  { "fflags", 0x001, "Floating-point exception flags" },
  { "frm", 0x002, "Floating-point dynamic rounding mode" },
  { "fcsr", 0x003, "Floating-point control and status" },
  { "cycle", 0xC00, "Cycle counter" },
  { "time", 0xC01, "Real-time clock" },
  { "instret", 0xC02, "Instructions-retired counter" },
  { "cycleh", 0xC80, "Upper 32 bits of `cycle` (RV32)" },
  { "timeh", 0xC81, "Upper 32 bits of `time` (RV32)" },
  { "instreth", 0xC82, "Upper 32 bits of `instret` (RV32)" },
  { "mstatus", 0x300, "Machine status" },
  { "misa", 0x301, "ISA and extensions" },
  { "medeleg", 0x302, "Machine exception delegation" },
  { "mideleg", 0x303, "Machine interrupt delegation" },
  { "mie", 0x304, "Machine interrupt enable" },
  { "mtvec", 0x305, "Machine trap vector base address" },
  { "mcounteren", 0x306, "Machine counter enable" },
  { "menvcfg", 0x30A, "Machine environment configuration" },
  { "mstatush", 0x310, "Machine status high (RV32)" },
  { "menvcfgh", 0x31A, "Machine environment configuration high (RV32)" },
  { "mcountinhibit", 0x320, "Machine counter inhibit" },
  { "mscratch", 0x340, "Machine scratch" },
  { "mepc", 0x341, "Machine exception program counter" },
  { "mcause", 0x342, "Machine trap cause" },
  { "mtval", 0x343, "Machine trap value" },
  { "mip", 0x344, "Machine interrupt pending" },
  { "mcycle", 0xB00, "Machine cycle counter" },
  { "minstret", 0xB02, "Machine instructions-retired counter" },
  { "mcycleh", 0xB80, "Upper 32 bits of `mcycle` (RV32)" },
  { "minstreth", 0xB82, "Upper 32 bits of `minstret` (RV32)" },
  { "mvendorid", 0xF11, "Machine vendor ID" },
  { "marchid", 0xF12, "Machine architecture ID" },
  { "mimpid", 0xF13, "Machine implementation ID" },
  { "mhartid", 0xF14, "Hardware thread ID" },
  { "mconfigptr", 0xF15, "Machine configuration pointer" },
  { "mseccfg", 0x747, "Machine security configuration" },
  { "mseccfgh", 0x757, "Machine security configuration high (RV32)" },
  { "sstatus", 0x100, "Supervisor status" },
  { "sie", 0x104, "Supervisor interrupt enable" },
  { "stvec", 0x105, "Supervisor trap vector base address" },
  { "scounteren", 0x106, "Supervisor counter enable" },
  { "senvcfg", 0x10A, "Supervisor environment configuration" },
  { "sscratch", 0x140, "Supervisor scratch" },
  { "sepc", 0x141, "Supervisor exception program counter" },
  { "scause", 0x142, "Supervisor trap cause" },
  { "stval", 0x143, "Supervisor trap value" },
  { "sip", 0x144, "Supervisor interrupt pending" },
  { "stimecmp", 0x14D, "Supervisor timer compare" },
  { "satp", 0x180, "Supervisor address translation and protection" },
}

for i = 0, 15 do
  csrs[#csrs + 1] = { "pmpcfg" .. i, 0x3A0 + i, "Physical memory protection configuration " .. i }
end
for i = 0, 63 do
  csrs[#csrs + 1] = { "pmpaddr" .. i, 0x3B0 + i, "Physical memory protection address " .. i }
end
for i = 3, 31 do
  csrs[#csrs + 1] = { "mhpmcounter" .. i, 0xB00 + i, "Machine performance-monitoring counter " .. i }
  csrs[#csrs + 1] = { "mhpmevent" .. i, 0x320 + i, "Machine performance-monitoring event selector " .. i }
end

local pseudo_by_label = {}
for _, p in ipairs(pseudos) do
  pseudo_by_label[p[1]] = p
end
local reg_by_label = {}
for _, r in ipairs(gprs) do
  reg_by_label[r[1]] = r
end
for _, r in ipairs(fprs) do
  reg_by_label[r[1]] = r
end
local csr_by_label = {}
for _, c in ipairs(csrs) do
  csr_by_label[c[1]] = c
end

local function pseudo_doc(p)
  return ("**%s** — %s\n\n```asm\n%s\n```"):format(p[1], p[3], p[2])
end

local function reg_doc(r)
  return ("**%s** — `%s`\n\n%s\n\nPreserved across calls: **%s**"):format(r[1], r[2], r[3], r[4])
end

local function csr_doc(c)
  return ("**%s** — CSR `0x%03X`\n\n%s"):format(c[1], c[2], c[3])
end

--- Look up docs for a word. Returns nil when the word is not one of the
--- supplemented RISC-V names (the caller should then fall back to the LSP).
--- @param word string
--- @param bufnr? integer
--- @return string?
function M.hover(word, bufnr)
  if bufnr and M.is_x86_asm(bufnr) then
    return nil
  end
  local p = pseudo_by_label[word]
  if p then
    return pseudo_doc(p)
  end
  local r = reg_by_label[word]
  if r then
    return reg_doc(r)
  end
  local c = csr_by_label[word]
  if c then
    return csr_doc(c)
  end
  return nil
end

--- Hover implementation for asm buffers: prefer our pseudo/register/CSR
--- docs, otherwise fall back to the real asm-lsp hover.
function M.hover_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local word = vim.fn.expand("<cword>")
  local doc = M.hover(word, bufnr)
  if not doc then
    -- `<cword>` stops at `.`, so retry with `<cWORD>` for fmv.s/fabs.d/etc.
    word = vim.fn.expand("<cWORD>"):gsub("[,;]+$", "")
    doc = M.hover(word, bufnr)
  end
  if doc then
    vim.lsp.util.open_floating_preview(vim.split(doc, "\n"), "markdown", {
      border = "rounded",
      focusable = false,
      close_events = { "CursorMoved", "CursorMovedI", "BufHidden", "InsertLeave" },
    })
  else
    vim.lsp.buf.hover()
  end
end

--- @param bufnr? integer
--- @return boolean
function M.is_x86_asm(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    -- AT&T x86 immediates ($1, $-1) and registers (%rax, %r8d, %xmm0).
    -- RISC-V's relocations use %hi()/%lo(), and its symbols can end in `$`
    -- (__global_pointer$), so only treat `$` followed by a digit/sign as x86.
    if
      line:find("%$[%d%-+]")
      or line:find("%%[re]?[abcd]x")
      or line:find("%%r[0-9]")
      or line:find("%%r[isbpd][ipd]")
      or line:find("%%[xyz]mm")
      or line:find("%%[cdefgs]s")
    then
      return true
    end
  end
  return false
end

local function completion_item_kind()
  local ok, types = pcall(require, "blink.cmp.types")
  return ok and types.CompletionItemKind or vim.lsp.protocol.CompletionItemKind
end

local source = {}

function source:enabled()
  return vim.bo.filetype == "asm"
end

function source:get_completions(ctx, callback)
  local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
  if M.is_x86_asm(bufnr) then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  local kind = completion_item_kind()
  local items = {}
  for _, p in ipairs(pseudos) do
    items[#items + 1] = {
      label = p[1],
      kind = kind.Keyword,
      detail = p[3],
      documentation = { kind = "markdown", value = pseudo_doc(p) },
      insertText = p[1],
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
  end
  for _, r in ipairs(gprs) do
    items[#items + 1] = {
      label = r[1],
      kind = kind.Variable,
      detail = ("%s · %s"):format(r[2], r[3]),
      documentation = { kind = "markdown", value = reg_doc(r) },
      insertText = r[1],
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
  end
  for _, r in ipairs(fprs) do
    items[#items + 1] = {
      label = r[1],
      kind = kind.Variable,
      detail = ("%s · %s"):format(r[2], r[3]),
      documentation = { kind = "markdown", value = reg_doc(r) },
      insertText = r[1],
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
  end
  for _, c in ipairs(csrs) do
    items[#items + 1] = {
      label = c[1],
      kind = kind.Constant,
      detail = ("0x%03X · %s"):format(c[2], c[3]),
      documentation = { kind = "markdown", value = csr_doc(c) },
      insertText = c[1],
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
  end

  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

function M.new()
  return setmetatable({}, { __index = source })
end

return M
