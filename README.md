# ZMIPS (Zach's MIPS) CPU

Despite the MIPS name, the architecture gradually changed away from MIPS to some combination of ARM, MIPS, 6502, and that RISC CPU I made last semester for another class. The original datapath and forwarding logic is based on that described in the famous *Computer Organization and Design* by Patterson/Hennessy. It's pronounced "ZIPS" (with a silent 'm' ;)

## Repo Directory Structure

```
.
├── README.md                   - You are here
├── test-data
│   ├── asm-output.dat          - Output of assembler
│   ├── asm-output.lst          - [gitignore'd] assembler listing file
│   ├── asm-output.mif          - [gitignore'd] assembler memory initialization file (for synthesis)
│   ├── testdata.dat            - Original hand-assembled test code
│   └── test_program.asm        - Basic test program
├── verilog
│   ├── tb_zmips.v              - Test bench for the CPU
│   ├── zmips_alu.v             - ALU module for CPU execute stage
│   ├── zmips_barrel_shift.v    - Generic behavioral barrel shifter
│   ├── zmips_mux232.v          - 2x1 32-bit mux
│   ├── zmips_mux432.v          - 4x1 32-bit mux
│   ├── zmips_n_adder.v         - Parameterized N-bit adder
│   ├── zmips_regfile.v         - Register file
│   └── zmips.v                 - Top Level Module for CPU
└── zmips_assembler.py          - Super basic python3-based assembler for the CPU
```

## Instruction layout
 
See `zmips.v`

## Registers

 | Number       | Description                                                                                    |
 | ------------ | ---------------------------------------------------------------------------------------------- |
 | `R0`         | Register loaded when loading immediate sign-extended (IMMDSE) data. Otherwise, general purpose |
 | `R1` - `R29` | General-purpose                                                                                |
 | `R30`        | PC value + 4 from the last JPL instruction                                                     |
 | `R31`        | The current PC value (PC + 4 from the instruction's PC due to pipeline)                        |

## Opcodes

*Note:* If you're clever with the instruction bits, you can combine instructions to do more than one operation simultaneously (such as LW/SW with complex addressing modes).

**Fields:**
* rd = destination register
* rs = source register "A"
* rt = source register "B"
* flags = Z, C, N - Optional, determine what status flags each operation affects

### NOP
Name: No OPeration   
Description: rd = rs + rt + C
```
000000_xxxxx_xxxxx_xxxxx_xxxxx_000xxx
```

### ADD rd, rs, rt [, flags]
Name: Add   
Description: rd = rs + rt + C
```
000100_sssss_ttttt_ddddd_xxxxx_000zcn
```

### SUB rd, rs, rt [, flags]
Name: Subtract   
Description: rd = rs - rt + C
```
000100_sssss_ttttt_ddddd_xxxxx_001zcn
```

### CMP rs, rt [, flags]
Name: Compare   
Description: [flags] = rs - rt (ignores carry flag)
```
000000_sssss_ttttt_ddddd_xxxxx_001zcn
```

### AND rd, rs, rt [, flags]
Name: logical And   
Description: rd = rs & rt
```
000100_sssss_ttttt_ddddd_xxxxx_010zcn
```

### OR rd, rs, rt [, flags]
Name: logical Or   
Description: rd = rs | rt
```
000100_sssss_ttttt_ddddd_xxxxx_100zcn
```

### EOR rd, rs, rt [, flags]
Name: logical exclusive-or   
Description: rd = rs ^ rt
```
000100_sssss_ttttt_ddddd_xxxxx_110zcn
```

### SLL rd, rs, shamt [, flags]
Name: Shift Left Logical   
Description: rd = rs << hhhhh
```
000101_sssss_xxxxx_ddddd_hhhhh_010zcn
```

### SRL rd, rs, shamt [, flags]
Name: Shift Right Logical   
Description: rd = rs >> hhhhh
```
000101_sssss_xxxxx_ddddd_hhhhh_110zcn
```

### SRA rd, rs, shamt [, flags]
Name: Shift Right Arithmetic   
Description: rd = rs >>> hhhhh [keeps sign]
```
000101_sssss_xxxxx_ddddd_hhhhh_100zcn
```

### MOV rd, rs [, flags]
Name: MOVe (copy)   
Description: rd = rs
```
000101_sssss_xxxxx_ddddd_xxxxx_000zcn
```

### JMP rs
Name: Jump to rs   
Description: pc = rs
```
000000_sssss_xxxxx_xxxxx_xxxxx_111111
```

### LW rd, rs
Name: Load Word   
Description: rd = data_memory[rs]
```
001101_sssss_xxxxx_ddddd_xxxxx_000000
```

### SW rs, rt
Name: Store Word   
Description: data_memory[rs] = rt
```
001001_sssss_ttttt_xxxxx_xxxxx_000000
```

### LI #se_immd
Name: Load Immediate   
Description: r0 = {6{immd[25]}, immd}
```
010101_iiiiiiiiiiiiiiiiiiiiiiiiii
```

### BFC flag, label
Name: Branch relative on flag clear   
Description: pc = pc + {4{immd[25]}, immd, 2'b00}
```
1000ff_iiiiiiiiiiiiiiiiiiiiiiiiii
```

### BFS flag, label
Name: Branch relative on flag set   
Description: pc = pc + {4{immd[25]}, immd, 2'b00}
```
1010ff_iiiiiiiiiiiiiiiiiiiiiiiiii
```

### JPL label
Name: JumP and Link   
Description: 
* r30 = pc + 4
* pc = immediate_address << 2
```
11_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### FFL flags
Name: Force FLags   
Description: zf = z, cf = c, nf = n
```
000011_xxxxx_xxxxx_xxxxx_xxxxx_000zcn
```
