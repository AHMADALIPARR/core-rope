# Core Rope ROM — 16 × 12 educational prototype

This project models a **conceptual** core-rope encoding and a small accumulator CPU. It is **not** a historically accurate Apollo Guidance Computer instruction set or a tested magnetic readout circuit.

## Run

```sh
python3 rope.py demo.asm --out build
python3 -m unittest discover -v
```

Outputs: `rom.hex`, `wiring.json`, `trace.json`. `wiring.json` lists each word's 12 sense-core routing decisions. Through = 1, around = 0 (a chosen convention, not a universal physical polarity). The emulator fetches from immutable ROM and writes to separate shadow RAM; a store never modifies the ROM image.

## Physical prototype architecture

- 16 selectable **word drive lines**; each line is threaded through or around **12 sense cores** per wiring map (192 routing decisions).
- Each of the 12 sense cores has an independent sense winding and a protected differential sensing channel.
- A selected drive-line current pulse couples into sense windings where that line passes through the relevant core. An around route is the zero state under the chosen convention.
- A decoder selects **exactly one** drive line. A current-limited pulse driver energizes it; a synchronized sample-and-latch circuit captures 12 sense outputs into a 12-bit register.
- A clocked controller sequences: select → settle → pulse → sample → release. Include blanking, hysteresis/threshold calibration, and readback comparison.
- Keep drive and sense grounds/return paths planned; use a low-voltage isolated bench supply, current limiting, and flyback/transient protection. **Do not connect unvalidated inductive coils directly to microcontroller GPIO.**

## Design assumptions and unresolved electrical engineering

The software routing map is verified by round-trip reconstruction, **not** by measured magnetic coupling. Ferrite permeability, geometry, number of sense turns, drive current, pulse width, mutual inductance, crosstalk, parasitic capacitance, comparator thresholds, and driver thermal limits must be measured on a one-bit test jig before selecting actual component values. A genuine core-rope assembly is a transformer-coupling ROM, **not** a writable magnetic-core memory array. Historical Apollo rope modules used a much more elaborate implementation than this educational layout.

## Bring-up and acceptance

1. Assemble and verify map round trip; independently check the printed map against the physical routing.
2. Build one sense core and two selectable word lines (one through, one around); measure induced waveforms with an oscilloscope.
3. Determine safe drive current and timing from measured waveforms and core/driver datasheets.
4. Expand to 12 bit planes and 16 word lines, with test patterns `000`, `FFF`, `AAA`, `555`, and walking ones/zeros.
5. Run at least 1,000 full read sweeps; require zero decoded errors under specified supply and temperature conditions before CPU integration.
6. Compare hardware reads against `rom.hex`; only then connect the instruction-fetch interface.

## Encoding and ISA

12-bit word: upper 4 bits opcode, lower 8 bits operand (only addresses 0–15 supported). NOP=0, LDA=1, ADD=2, STA=3, JMP=4, JZ=5, HLT=6; DAT stores a raw 12-bit value. The 16-word memory is a toy scale; larger programs require wider addressing, more word lines, and revised timing.
