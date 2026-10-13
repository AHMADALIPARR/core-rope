export type Example = {
  id: string;
  name: string;
  note: string;
  source: string;
};

export const SUM_SOURCE = `; The immutable ROM contains code and constants; STA writes only to shadow RAM.
START: LDA VALUE
       ADD ONE
       STA RESULT
       HLT
VALUE: DAT 41
ONE:   DAT 1
RESULT: DAT 0
`;

const COUNTDOWN_SOURCE = `; Count 3 down to 0. JZ leaves the loop. NEG is -1 in twelve bits.
START: LDA COUNT
LOOP:  ADD NEG
       STA COUNT
       JZ DONE
       JMP LOOP
DONE:  HLT
COUNT: DAT 3
NEG:   DAT 4095
`;

const WRAP_SOURCE = `; 4000 + 200 wraps modulo 4096.
       LDA A
       ADD B
       STA SUM
       HLT
A:     DAT 4000
B:     DAT 200
SUM:   DAT 0
`;

const IMMUTABLE_SOURCE = `; STA hits the next word in shadow RAM. The fetch still comes off the rope.
       LDA ZERO
       STA TARGET
TARGET: LDA VALUE
       HLT
ZERO:  DAT 0
VALUE: DAT 9
`;

function pattern(title: string, valueAt: (address: number) => number): string {
  const lines = [`; ${title}`, "; Sense pattern. Pulse a word line. A run may fault on an illegal opcode."];
  for (let address = 0; address < 16; address += 1) {
    const value = valueAt(address) & 0xfff;
    const tag = address.toString(16).toUpperCase();
    lines.push(`W${tag}: DAT 0x${value.toString(16).toUpperCase().padStart(3, "0")}`);
  }
  return lines.join("\n");
}

export const EXAMPLES: readonly Example[] = [
  {
    id: "sum",
    name: "Sum",
    note: "41 + 1. The store lands in shadow RAM. The rope word stays 0.",
    source: SUM_SOURCE,
  },
  {
    id: "countdown",
    name: "Countdown",
    note: "JZ leaves the loop when the accumulator is zero.",
    source: COUNTDOWN_SOURCE,
  },
  {
    id: "wrap",
    name: "Wrap",
    note: "Twelve-bit addition wraps at 4096. 4000 + 200 becomes 104.",
    source: WRAP_SOURCE,
  },
  {
    id: "immutable",
    name: "Immutable",
    note: "A store onto the next instruction does not change the fetch.",
    source: IMMUTABLE_SOURCE,
  },
  {
    id: "zeros",
    name: "000",
    note: "Every sense core should read zero.",
    source: pattern("Pattern 000", () => 0),
  },
  {
    id: "ones",
    name: "FFF",
    note: "Every sense core should read one.",
    source: pattern("Pattern FFF", () => 0xfff),
  },
  {
    id: "aaa",
    name: "AAA",
    note: "Alternating ones on the odd cores.",
    source: pattern("Pattern AAA", () => 0xaaa),
  },
  {
    id: "555",
    name: "555",
    note: "Alternating ones on the even cores.",
    source: pattern("Pattern 555", () => 0x555),
  },
  {
    id: "walk1",
    name: "Walk 1",
    note: "One through-core walks from core 0 up.",
    source: pattern("Walking ones", (address) => 1 << (address % 12)),
  },
  {
    id: "walk0",
    name: "Walk 0",
    note: "One around-core walks from core 0 up.",
    source: pattern("Walking zeros", (address) => 0xfff ^ (1 << (address % 12))),
  },
];
