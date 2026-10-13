import { MASK, MAX_STEPS, OPS, WORD_COUNT } from "./isa.ts";

export type TraceEntry = {
  pc: number;
  word: number;
  op: number;
  addr: number;
  accBefore: number;
  accAfter: number;
  pcAfter: number;
  write: { address: number; value: number } | null;
  halted: boolean;
};

export type Machine = {
  /** Immutable rope image. Fetches always read this, never RAM. */
  rom: readonly number[];
  ram: number[];
  pc: number;
  acc: number;
  halted: boolean;
  fault: string | null;
  trace: TraceEntry[];
};

export function boot(words: readonly number[]): Machine {
  const rom = Array.from({ length: WORD_COUNT }, (_, address) => (words[address] ?? 0) & MASK);
  return { rom, ram: rom.slice(), pc: 0, acc: 0, halted: false, fault: null, trace: [] };
}

export function step(machine: Machine, maxSteps = MAX_STEPS): Machine {
  if (machine.halted || machine.fault) return machine;
  if (machine.pc < 0 || machine.pc >= WORD_COUNT) {
    return { ...machine, fault: "PC outside ROM" };
  }
  if (machine.trace.length >= maxSteps) {
    return { ...machine, fault: "execution step limit reached" };
  }

  const word = machine.rom[machine.pc] ?? 0;
  const op = word >> 8;
  const addr = word & 0xff;
  const seen: TraceEntry = {
    pc: machine.pc,
    word,
    op,
    addr,
    accBefore: machine.acc,
    accAfter: machine.acc,
    pcAfter: machine.pc,
    write: null,
    halted: false,
  };

  if (op > 6) {
    return { ...machine, fault: `bad opcode ${op} at ${machine.pc}`, trace: [...machine.trace, seen] };
  }
  if (op >= 1 && op <= 5 && addr >= WORD_COUNT) {
    return { ...machine, fault: "bad address", trace: [...machine.trace, seen] };
  }

  let pc = machine.pc + 1;
  let acc = machine.acc;
  let ram = machine.ram;
  let write: TraceEntry["write"] = null;

  if (op === OPS.LDA) acc = (ram[addr] ?? 0) & MASK;
  else if (op === OPS.ADD) acc = (acc + (ram[addr] ?? 0)) & MASK;
  else if (op === OPS.STA) {
    ram = machine.ram.slice();
    const stored = acc & MASK;
    ram[addr] = stored;
    write = { address: addr, value: stored };
  } else if (op === OPS.JMP) pc = addr;
  else if (op === OPS.JZ && acc === 0) pc = addr;
  else if (op === OPS.HLT) {
    return {
      ...machine,
      halted: true,
      trace: [...machine.trace, { ...seen, halted: true, pcAfter: machine.pc }],
    };
  }

  return {
    ...machine,
    pc,
    acc: acc & MASK,
    ram,
    trace: [...machine.trace, { ...seen, accAfter: acc & MASK, pcAfter: pc, write }],
  };
}

export function runMachine(start: Machine, maxSteps = MAX_STEPS): Machine {
  let current = start;
  for (;;) {
    if (current.halted || current.fault) return current;
    const next = step(current, maxSteps);
    if (next.halted || next.fault) return next;
    if (next.trace.length === current.trace.length) {
      return { ...next, fault: "execution step limit reached" };
    }
    current = next;
  }
}

export function run(words: readonly number[], maxSteps = MAX_STEPS): Machine {
  return runMachine(boot(words), maxSteps);
}
