# Integer BASIC IR

Two native programs read the same numbered BASIC and produce the same magazine.

One is FreeBASIC. One is NASM x86-64, using Linux system calls and no C library. There is no Python, TypeScript, or JavaScript in this implementation.

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

`R3` is 432. The magazine is 8 records of 68 bytes. Both programs write the same bytes, and the terminal checksum is `580d19b82098e32d`.

## Build

FreeBASIC 1.10 and NASM are required, plus `ld`.

```sh
./scripts/build.sh
./scripts/test.sh
```

```sh
./build/basic-ir run fixtures/programs/sample.bas build/sample.bin
./build/asm-ir verify build/sample.bin
```

`run` prints the terminal checksum. `verify` recomputes the chain. `selftest` checks SHA-256, the sample, a bad opcode, division by zero, memory, and a taken `JZ`.

## Record

Each instruction appends one little-endian record: version, sequence, line number, opcode, flags, three arguments, result, previous checksum, checksum. The arguments are the instruction fields. The result is the value the operation produced.

The checksum is the first 8 bytes of SHA-256 over the previous checksum, line, opcode, arguments, result, and sequence, read as a little-endian 64-bit integer. The chain starts at `DEADBEEFCAFEBABE` hex. A program cannot supply the checksum. Changing any earlier byte makes `verify` fail.

The opcode numbers, syscall ids, and the 54-byte hash layout are in [spec/integer-ir.md](spec/integer-ir.md).

## What this is not

This is not a web app, and it is not a Python port of the runtime. The FreeBASIC program and the assembly program each parse, execute, hash, and verify on their own. The test compares their magazines. It does not treat one of them as a wrapper around the other.
