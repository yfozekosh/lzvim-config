local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local cycles = require("disasm.cycles")
local parser = require("disasm.parser")

local elf = "/home/yfozekosh/Projects/mtrx_asm/out/firmware.elf"
local objdump = "/home/yfozekosh/.local/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump"
local result = vim.system({ objdump, "-d", "-l", "-C", elf }, { text = true }):wait()
local lines = vim.split(result.stdout or "", "\n", { plain = true })
local sizes = cycles.parse_sizes(lines)
local parsed = parser.parse(lines)
local computed = cycles.compute(parsed.lines, {
  sizes = sizes,
  latency = 0,
  is_flash = function(addr)
    return addr < 0x4000
  end,
})

local missing = {}
for _, insn in ipairs(computed.instructions) do
  if not computed.line_annotations[insn.row] then
    missing[#missing + 1] = {
      row = insn.row,
      addr = string.format("%x", insn.addr),
      size = insn.size,
      mnemonic = insn.mnemonic,
      operands = insn.operands,
      block_start = computed.annotations[insn.row] ~= nil,
    }
  end
end

print("instructions=" .. #computed.instructions)
print("annotated_blocks=" .. tostring(vim.tbl_count(computed.annotations)))
print("missing_lines=" .. #missing)
for i = 1, math.min(#missing, 120) do
  local m = missing[i]
  print(string.format(
    "row=%d addr=%s size=%s %s %s block_start=%s",
    m.row,
    m.addr,
    tostring(m.size),
    m.mnemonic,
    m.operands,
    tostring(m.block_start)
  ))
end
