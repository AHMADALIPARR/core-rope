# Integer BASIC IR

This is the behavior both native programs implement. It is not a Python program, not a TypeScript program, and not a JavaScript program.

## Source

A program is a sequence of numbered lines.

```
10 LOAD R0, 17
20 LOAD R1, 23
30 MUL R2, R0, R1
40 ADD R3, R2, 41
50 CHECK R3
60 SYSCALL CALCULATE, R3
70 SEAL
80 HALT
```

`#` or `REM` starts a comment. Mnemonics and register names are case-insensitive. Commas separate operands. A line number is required and may not repeat.

## Opcodes

| Name | Id | Operands | flags bit 0 |
| --- | --- | --- | --- |
| LOAD | 1 | Rd, imm | 0 |
| MOVE | 2 | Rd, Rs | 0 |
| ADD | 3 | Rd, Ra, Rb or imm | 1 if the last operand is an immediate |
| SUB | 4 | Rd, Ra, Rb or imm | same |
| MUL | 5 | Rd, Ra, Rb or imm | same |
| DIV | 6 | Rd, Ra, Rb or imm | same |
| MOD | 7 | Rd, Ra, Rb or imm | same |
| CMP | 8 | Ra, Rb or imm | 1 if the second operand is an immediate |
| JMP | 9 | line | 0 |
| JZ | 10 | line | 0 |
| JNZ | 11 | line | 0 |
| LOADM | 12 | Rd, addr or Rs | 1 if the address is an immediate |
| STOREM | 13 | Rs, addr or Ra | 1 if the address is an immediate |
| CHECK | 14 | Rd | 0 |
| SYSCALL | 15 | NAME, Rd | 0 |
| SEAL | 16 | none | 0 |
| HALT | 255 | none | 0 |

Registers are R0 through R31. Arithmetic is signed 64-bit two's complement and wraps. Division or remainder by zero is a fault. Memory is 4096 signed words. An address outside that range is a fault. A jump to a missing line is a fault. Unknown opcodes, unknown syscalls, and missing capabilities are faults.

## Execution

Instructions run in source order. `JMP` always redirects. `JZ` redirects when the last `CMP` result was 0. `JNZ` redirects when it was not 0. `SEAL` and `HALT` stop the machine. `SYSCALL` writes its return value back into the named register.

The sample program must leave 432 in R3: 17 × 23 = 391, and 391 + 41 = 432. `CALCULATE` returns its argument unchanged.

Syscall ids: CALCULATE 1, READ 2, WRITE 3, CHECKSUM 4, SEAL 5. `CHECKSUM` returns the argument xor `A5A5A5A5A5A5A5A5` hex. The default run grants every capability.

## Record

Each executed instruction appends one 68-byte little-endian record:

```
u32 version = 1
u64 sequence          first record is 1
u32 program_counter   the BASIC line number
u16 opcode
u16 flags
i64 arg0
i64 arg1
i64 arg2
i64 result
u64 previous_checksum
u64 checksum
```

The arguments stored are the instruction fields, not the registers they point at. `result` is the value the operation produced.

## Checksum

H0 is the low 64 bits of `BA51C0001A6E4711DEADBEEFCAFEBABE` hex, which is `DEADBEEFCAFEBABE` hex.

The hash input, little-endian, is:

```
u64 previous
u32 program_counter
u16 opcode
i64 arg0
i64 arg1
i64 arg2
i64 result
u64 sequence
```

That is 54 bytes. The checksum is the first 8 bytes of SHA-256, read as a little-endian unsigned 64-bit integer. The runtime computes it. A program cannot supply it.

A magazine is the raw concatenation of those records. Verification recomputes the chain from H0. A sealed magazine rejects further appends. A changed historical record fails verification.
