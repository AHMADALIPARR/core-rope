# Core Rope

Educational 16×12 core-rope assembler, wiring map, and accumulator. A word line passes **through** a sense core for a one and **around** it for a zero. Core 0 is the least significant bit.

This is a conceptual encoding. It is not an Apollo Guidance Computer, and it is not a measured magnetic circuit.

The bench fetches from the rope and writes only to shadow RAM. A store never rewrites the image.

## Demo

```
START: LDA VALUE
       ADD ONE
       STA RESULT
       HLT
VALUE: DAT 41
ONE:   DAT 1
RESULT: DAT 0
```

Assembled image: `104 205 306 600 029 001 000 …`. After halt the accumulator is **42** (`02A`). Shadow word `06` holds 42. Rope word `06` is still `000`.

## ISA

Twelve-bit word. Upper four bits are the opcode. The low eight bits are the operand; only addresses 0–15 are legal.

| Op | Code | Effect |
| --- | --- | --- |
| NOP | 0 | No effect |
| LDA | 1 | ACC ← RAM[a] |
| ADD | 2 | ACC ← (ACC + RAM[a]) mod 4096 |
| STA | 3 | RAM[a] ← ACC |
| JMP | 4 | PC ← a |
| JZ | 5 | If ACC is 0, PC ← a |
| HLT | 6 | Stop |
| DAT | — | Raw 12-bit word |

Labels, `;` comments, decimal, and `0x` / `0b` / `0o` literals are accepted. Forward references resolve in the second pass. Unallocated words read as NOP.

## Layout

- `src/lib/rope/` — assembler, round-trip wiring check, and the machine
- `src/components/rope/` — the bench
- `reference/` — the original single-file prototype, unchanged

## Bring-up

Prove one sense core and two word lines on a scope before choosing current or timing. Patterns `000`, `FFF`, `AAA`, `555`, walking ones, and walking zeros should match the hex image for a thousand clean sweeps before any controller is attached.

Do not connect an unvalidated inductive load to a microcontroller pin. Use a current-limited driver, a planned return path, and flyback protection.

## License

Copyright (C) 2026 Ahmad Parr.

Core Rope is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

The verbatim license is [LICENSE](LICENSE). If you run a modified version on a network server, section 13 requires you to offer its users the corresponding source.
