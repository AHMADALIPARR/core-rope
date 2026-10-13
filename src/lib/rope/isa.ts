/** 16×12 educational rope. Through = 1, around = 0, core 0 = LSB. */

export const WORD_COUNT = 16;
export const BIT_COUNT = 12;
export const MASK = 0xfff;
export const MAX_STEPS = 100;

export const OPS = {
  NOP: 0,
  LDA: 1,
  ADD: 2,
  STA: 3,
  JMP: 4,
  JZ: 5,
  HLT: 6,
} as const;

export type OpName = keyof typeof OPS;

const OP_NAMES = new Set<string>(Object.keys(OPS));

export function isOp(name: string): name is OpName {
  return OP_NAMES.has(name);
}

export function hex3(word: number): string {
  return (word & MASK).toString(16).toUpperCase().padStart(3, "0");
}

export function hex2(value: number): string {
  return (value & 0xff).toString(16).toUpperCase().padStart(2, "0");
}

export function bits12(word: number): string {
  return (word & MASK).toString(2).padStart(BIT_COUNT, "0");
}

/** Python `int(token, 0)` for the literals this bench accepts. */
export function parseLiteral(token: string): number | null {
  let text = token.trim().toUpperCase();
  if (!text) return null;
  let sign = 1;
  if (text.startsWith("+")) text = text.slice(1);
  else if (text.startsWith("-")) {
    sign = -1;
    text = text.slice(1);
  }
  if (!text) return null;
  if (text.startsWith("0X")) {
    if (!/^0X[0-9A-F]+$/.test(text)) return null;
    return sign * Number.parseInt(text.slice(2), 16);
  }
  if (text.startsWith("0B")) {
    if (!/^0B[01]+$/.test(text)) return null;
    return sign * Number.parseInt(text.slice(2), 2);
  }
  if (text.startsWith("0O")) {
    if (!/^0O[0-7]+$/.test(text)) return null;
    return sign * Number.parseInt(text.slice(2), 8);
  }
  if (!/^[0-9]+$/.test(text)) return null;
  return sign * Number.parseInt(text, 10);
}

const NAMES = ["NOP", "LDA", "ADD", "STA", "JMP", "JZ", "HLT"] as const;

export function mnemonic(op: number, addr: number, labels?: Record<string, number>): string {
  if (op < 0 || op > 6) return `OP ${op}`;
  const name = NAMES[op] ?? "OP";
  if (op === 0 || op === 6) return name;
  const symbol = labels
    ? Object.entries(labels).find(([, value]) => value === addr)?.[0]
    : undefined;
  return `${name} ${symbol ?? String(addr)}`;
}
