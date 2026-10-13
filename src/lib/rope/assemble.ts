import { BIT_COUNT, MASK, WORD_COUNT, bits12, hex3, isOp, parseLiteral } from "./isa.ts";
import type { OpName } from "./isa.ts";
import { OPS } from "./isa.ts";

const LABEL = /^[A-Z_][A-Z_0-9]*$/;

export class AssembleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AssembleError";
  }
}

export type Origin = "op" | "dat" | "pad";

export type WiringRow = {
  address: number;
  word: number;
  hex: string;
  binary: string;
  throughCores: number[];
  aroundCores: number[];
};

export type ListingLine = {
  address: number;
  word: number;
  hex: string;
  binary: string;
  mnemonic: string;
  labels: string[];
  origin: Origin;
};

export type Image = {
  words: number[];
  origins: Origin[];
  labels: Record<string, number>;
  listing: ListingLine[];
  rows: WiringRow[];
  checksum: number;
};

export function wiring(words: readonly number[]): WiringRow[] {
  return words.map((word, address) => {
    const value = word & MASK;
    const throughCores: number[] = [];
    const aroundCores: number[] = [];
    for (let bit = 0; bit < BIT_COUNT; bit += 1) {
      if ((value & (1 << bit)) !== 0) throughCores.push(bit);
      else aroundCores.push(bit);
    }
    return {
      address,
      word: value,
      hex: hex3(value),
      binary: bits12(value),
      throughCores,
      aroundCores,
    };
  });
}

export function verify(words: readonly number[], rows: readonly WiringRow[]): void {
  if (rows.length !== words.length) throw new Error("wiring round-trip failed");
  for (let address = 0; address < words.length; address += 1) {
    const row = rows[address];
    if (!row || row.address !== address) throw new Error("wiring round-trip failed");
    const joined = [...row.throughCores, ...row.aroundCores].sort((a, b) => a - b);
    if (joined.length !== BIT_COUNT || joined.some((bit, index) => bit !== index)) {
      throw new Error("wiring round-trip failed");
    }
    if (row.throughCores.some((bit) => row.aroundCores.includes(bit))) {
      throw new Error("wiring round-trip failed");
    }
    const decoded = row.throughCores.reduce((sum, bit) => sum + (1 << bit), 0);
    if (decoded !== ((words[address] ?? 0) & MASK)) throw new Error(`word ${address} mismatch`);
  }
}

export function checksum(words: readonly number[]): number {
  return words.reduce((sum, word) => (sum + (word & MASK)) & MASK, 0);
}

export function threadSentence(row: WiringRow): string {
  const line = row.address.toString().padStart(2, "0");
  if (row.throughCores.length === 0) {
    return `Word line ${line} (${row.hex}) routes around all twelve sense cores.`;
  }
  if (row.aroundCores.length === 0) {
    return `Word line ${line} (${row.hex}) passes through all twelve sense cores.`;
  }
  return `Word line ${line} (${row.hex}) passes through cores ${row.throughCores.join(", ")} and around ${row.aroundCores.join(", ")}.`;
}

function resolve(
  lineno: number,
  token: string,
  labels: ReadonlyMap<string, number>,
  max: number,
): number {
  const key = token.toUpperCase();
  const named = labels.get(key);
  const value = named ?? parseLiteral(key);
  if (value === null || value === undefined) {
    throw new AssembleError(`line ${lineno}: unknown name ${token}`);
  }
  if (value < 0 || value > max) {
    throw new AssembleError(
      max === MASK ? "DAT out of range" : `line ${lineno}: address out of range`,
    );
  }
  return value;
}

export function assemble(source: string): Image {
  if (source.length > 8000) throw new AssembleError("source too long");
  const labels = new Map<string, number>();
  const labelOrder: string[] = [];
  const entries: { lineno: number; parts: string[] }[] = [];
  let pc = 0;

  for (const [index, raw] of source.split(/\r?\n/).entries()) {
    const lineno = index + 1;
    let line = (raw.split(";", 1)[0] ?? "").trim();
    if (!line) continue;
    if (line.includes(":")) {
      const splitAt = line.indexOf(":");
      const label = line.slice(0, splitAt).trim().toUpperCase();
      if (!LABEL.test(label) || labels.has(label)) {
        throw new AssembleError(`line ${lineno}: bad/duplicate label`);
      }
      labels.set(label, pc);
      labelOrder.push(label);
      line = line.slice(splitAt + 1).trim();
      if (!line) continue;
    }
    const parts = line
      .toUpperCase()
      .split(/[\s,]+/)
      .filter((part) => part.length > 0);
    const op = parts[0];
    if (!op || (!isOp(op) && op !== "DAT")) {
      throw new AssembleError(`line ${lineno}: unknown instruction ${op ?? ""}`);
    }
    entries.push({ lineno, parts });
    pc += 1;
  }
  if (pc > WORD_COUNT) throw new AssembleError("prototype ROM exceeds 16 words");

  const words: number[] = [];
  const origins: Origin[] = [];
  const mnemonics: string[] = [];

  for (const entry of entries) {
    const op = entry.parts[0] ?? "";
    const args = entry.parts.slice(1);
    if (op === "DAT") {
      if (args.length !== 1) throw new AssembleError(`line ${entry.lineno}: DAT needs value`);
      const token = args[0] ?? "";
      words.push(resolve(entry.lineno, token, labels, MASK));
      origins.push("dat");
      mnemonics.push(`DAT ${token.toUpperCase()}`);
      continue;
    }
    if (!isOp(op)) throw new AssembleError(`line ${entry.lineno}: unknown instruction ${op}`);
    const needs = op === "NOP" || op === "HLT" ? 0 : 1;
    if (args.length !== needs) throw new AssembleError(`line ${entry.lineno}: operand count`);
    let addr = 0;
    if (needs === 1) {
      addr = resolve(entry.lineno, args[0] ?? "", labels, WORD_COUNT - 1);
    }
    const opcode: number = OPS[op as OpName];
    words.push((opcode << 8) | addr);
    origins.push("op");
    mnemonics.push(needs === 1 ? `${op} ${(args[0] ?? "").toUpperCase()}` : op);
  }

  while (words.length < WORD_COUNT) {
    words.push(0);
    origins.push("pad");
    mnemonics.push("NOP");
  }

  const labelsAt: string[][] = Array.from({ length: WORD_COUNT }, () => []);
  const labelRecord: Record<string, number> = {};
  for (const name of labelOrder) {
    const address = labels.get(name);
    if (address === undefined) continue;
    labelRecord[name] = address;
    if (address >= 0 && address < WORD_COUNT) labelsAt[address]?.push(name);
  }

  const rows = wiring(words);
  verify(words, rows);

  const listing: ListingLine[] = words.map((word, address) => ({
    address,
    word,
    hex: hex3(word),
    binary: bits12(word),
    mnemonic: mnemonics[address] ?? "NOP",
    labels: labelsAt[address] ?? [],
    origin: origins[address] ?? "pad",
  }));

  return {
    words,
    origins,
    labels: labelRecord,
    listing,
    rows,
    checksum: checksum(words),
  };
}
