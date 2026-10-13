import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { assemble, verify, wiring } from "./assemble.ts";
import { EXAMPLES } from "./examples.ts";
import { boot, run, step } from "./machine.ts";

function source(id: string): string {
  const found = EXAMPLES.find((item) => item.id === id);
  if (!found) throw new Error(id);
  return found.source;
}

describe("assemble", () => {
  it("seats the demo rope and matches the prototype hex image", () => {
    const image = assemble(source("sum"));
    assert.deepEqual(image.words, [
      0x104, 0x205, 0x306, 0x600, 41, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);
    assert.equal(image.words.map((word) => word.toString(16).toUpperCase().padStart(3, "0")).join("\n") + "\n",
      "104\n205\n306\n600\n029\n001\n000\n000\n000\n000\n000\n000\n000\n000\n000\n000\n",
    );
    assert.equal(image.checksum, 0xc39);
    assert.deepEqual(image.rows[0]?.throughCores, [2, 8]);
    verify(image.words, image.rows);
  });

  it("accepts lowercase, comments, and a comma", () => {
    const image = assemble("start: lda value ; load\nadd, one\nhlt\nvalue: dat 41\none: dat 0x1\n");
    assert.equal(image.words[0], 0x103);
    assert.equal(image.words[1], 0x204);
    assert.equal(image.labels.VALUE, 3);
  });

  it("rejects range, duplicate, and length errors", () => {
    assert.throws(() => assemble("DAT 4096"), /DAT out of range/);
    assert.throws(() => assemble("JMP 16"), /address out of range/);
    assert.throws(() => assemble("A: NOP\nA: HLT"), /duplicate/);
    assert.throws(() => assemble("JMP NOWHERE"), /unknown name/);
    assert.throws(() => assemble("FOO 1"), /unknown instruction/);
    assert.throws(() => assemble(`${"NOP\n".repeat(17)}`), /16 words/);
    assert.throws(() => assemble("LDA"), /operand count/);
  });

  it("round-trips the sense patterns", () => {
    const aaa = wiring([0xaaa]);
    assert.deepEqual(aaa[0]?.throughCores, [1, 3, 5, 7, 9, 11]);
    const alt = wiring([0x555]);
    assert.deepEqual(alt[0]?.throughCores, [0, 2, 4, 6, 8, 10]);
    assert.deepEqual(wiring([1])[0]?.throughCores, [0]);
    assert.deepEqual(wiring([0x800])[0]?.throughCores, [11]);
    assert.deepEqual(wiring([0])[0]?.throughCores, []);
    assert.deepEqual(wiring([0xfff])[0]?.throughCores, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    for (const id of ["zeros", "ones", "aaa", "555", "walk1", "walk0"]) {
      const image = assemble(source(id));
      verify(image.words, image.rows);
    }
    const walk = assemble(source("walk1"));
    assert.deepEqual(walk.rows[0]?.throughCores, [0]);
    assert.deepEqual(walk.rows[11]?.throughCores, [11]);
  });
});

describe("machine", () => {
  it("adds 41 and 1 into shadow RAM and leaves the rope", () => {
    const image = assemble(source("sum"));
    const machine = run(image.words);
    assert.equal(machine.halted, true);
    assert.equal(machine.fault, null);
    assert.equal(machine.acc, 42);
    assert.equal(machine.pc, 3);
    assert.equal(machine.ram[6], 42);
    assert.equal(machine.rom[6], 0);
    assert.equal(image.words[6], 0);
    assert.deepEqual(
      machine.trace.map((entry) => entry.word),
      [0x104, 0x205, 0x306, 0x600],
    );
  });

  it("counts down and stops on JZ", () => {
    const image = assemble(source("countdown"));
    const machine = run(image.words);
    const count = image.labels.COUNT ?? -1;
    assert.equal(machine.halted, true);
    assert.equal(machine.acc, 0);
    assert.equal(machine.ram[count], 0);
    assert.equal(machine.rom[count], 3);
    assert.equal(machine.trace.length, 13);
  });

  it("wraps a twelve-bit add", () => {
    const image = assemble(source("wrap"));
    const machine = run(image.words);
    assert.equal(machine.acc, 104);
    assert.equal(machine.ram[image.labels.SUM ?? -1], 104);
    assert.equal(machine.rom[image.labels.SUM ?? -1], 0);
  });

  it("fetches the rope after a store onto that word", () => {
    const image = assemble(source("immutable"));
    const machine = run(image.words);
    const target = image.labels.TARGET ?? -1;
    assert.equal(machine.halted, true);
    assert.equal(machine.acc, 9);
    assert.equal(machine.ram[target], 0);
    assert.equal(machine.rom[target], 0x105);
  });

  it("stops a tight jump at the step limit", () => {
    const image = assemble("LOOP: JMP LOOP\n");
    const machine = run(image.words);
    assert.equal(machine.halted, false);
    assert.equal(machine.fault, "execution step limit reached");
    assert.equal(machine.trace.length, 100);
  });

  it("does not take JZ when the accumulator is nonzero", () => {
    const image = assemble("LDA ONE\nJZ SKIP\nLDA TWO\nHLT\nSKIP: HLT\nONE: DAT 1\nTWO: DAT 2\n");
    const machine = run(image.words);
    assert.equal(machine.acc, 2);
    assert.equal(machine.halted, true);
  });

  it("leaves PC on HLT", () => {
    const image = assemble("HLT\n");
    const once = step(boot(image.words));
    assert.equal(once.halted, true);
    assert.equal(once.pc, 0);
    assert.equal(step(once), once);
  });
});
