import { useReducer } from "react";
import { assemble } from "@/lib/rope/assemble";
import type { Image } from "@/lib/rope/assemble";
import { EXAMPLES } from "@/lib/rope/examples";
import { hex2, hex3, mnemonic } from "@/lib/rope/isa";
import { boot, runMachine, step } from "@/lib/rope/machine";
import type { Machine } from "@/lib/rope/machine";
import { Loom } from "@/components/rope/loom";
import { ControlButton, Panel } from "@/components/rope/ui";

type State = {
  source: string;
  exampleId: string;
  image: Image | null;
  error: string | null;
  machine: Machine | null;
  selected: number;
  sense: number | null;
  senseFrom: number | null;
};

type Action =
  | { type: "source"; source: string }
  | { type: "load"; id: string; source: string }
  | { type: "select"; address: number }
  | { type: "pulse" }
  | { type: "step" }
  | { type: "run" }
  | { type: "reset" };

const ISA = [
  ["NOP", "0", "No effect"],
  ["LDA", "1", "ACC ← RAM[a]"],
  ["ADD", "2", "ACC ← (ACC + RAM[a]) mod 4096"],
  ["STA", "3", "RAM[a] ← ACC. The rope is not written."],
  ["JMP", "4", "PC ← a"],
  ["JZ", "5", "If ACC is 0, PC ← a"],
  ["HLT", "6", "Stop. The bench leaves PC on this word."],
  ["DAT", "—", "Raw twelve-bit word or address constant"],
] as const;

function load(source: string, exampleId: string, execute: boolean): State {
  try {
    const image = assemble(source);
    const booted = boot(image.words);
    const machine = execute ? runMachine(booted) : booted;
    const last = machine.trace.at(-1);
    return {
      source,
      exampleId,
      image,
      error: null,
      machine,
      selected: execute ? machine.pc : 0,
      sense: last?.word ?? null,
      senseFrom: last?.pc ?? null,
    };
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : "assemble failed";
    return {
      source,
      exampleId,
      image: null,
      error: message,
      machine: null,
      selected: 0,
      sense: null,
      senseFrom: null,
    };
  }
}

function init(): State {
  const demo = EXAMPLES[0];
  if (!demo) return load("", "custom", false);
  return load(demo.source, demo.id, true);
}

function reduce(state: State, action: Action): State {
  switch (action.type) {
    case "source":
      return load(action.source, "custom", false);
    case "load":
      return load(action.source, action.id, false);
    case "select":
      return { ...state, selected: action.address };
    case "pulse": {
      if (!state.image) return state;
      return {
        ...state,
        sense: state.image.words[state.selected] ?? 0,
        senseFrom: state.selected,
      };
    }
    case "step": {
      if (!state.machine || state.machine.halted || state.machine.fault) return state;
      const machine = step(state.machine);
      const last = machine.trace.at(-1);
      return {
        ...state,
        machine,
        selected: machine.pc,
        sense: last?.word ?? state.sense,
        senseFrom: last?.pc ?? state.senseFrom,
      };
    }
    case "run": {
      if (!state.image) return state;
      const start =
        state.machine && !state.machine.halted && !state.machine.fault
          ? state.machine
          : boot(state.image.words);
      const machine = runMachine(start);
      const last = machine.trace.at(-1);
      return {
        ...state,
        machine,
        selected: machine.pc,
        sense: last?.word ?? null,
        senseFrom: last?.pc ?? null,
      };
    }
    case "reset": {
      if (!state.image) return state;
      return {
        ...state,
        machine: boot(state.image.words),
        selected: 0,
        sense: null,
        senseFrom: null,
      };
    }
    default:
      return state;
  }
}

function phaseOf(machine: Machine | null, error: string | null): string {
  if (error || !machine) return "Open";
  if (machine.fault) return "Fault";
  if (machine.halted) return "Halted";
  if (machine.trace.length === 0) return "Ready";
  return "Live";
}

function outcome(machine: Machine | null, error: string | null): string {
  if (error) return error;
  if (!machine) return "The rope is open.";
  if (machine.fault) return machine.fault;
  const acc = `${hex3(machine.acc)} (${machine.acc})`;
  const dirty = machine.ram.flatMap((word, address) =>
    word !== machine.rom[address] ? [hex2(address)] : [],
  );
  if (machine.halted) {
    if (dirty.length === 0) return `Halted. Accumulator ${acc}. Shadow still matches the rope.`;
    return `Halted. Accumulator ${acc}. Shadow differs at ${dirty.join(", ")}. The rope did not change.`;
  }
  if (machine.trace.length === 0) {
    return "Ready at word 00. Pulse latches one drive line. Run fetches until halt.";
  }
  return `Live. Accumulator ${acc}.`;
}

export function Workbench() {
  const [state, dispatch] = useReducer(reduce, undefined, init);
  const { image, machine, error } = state;
  const example = EXAMPLES.find((item) => item.id === state.exampleId);
  const blocked = !image || !machine;
  const pcLine = image && machine ? image.listing[machine.pc] : undefined;

  return (
    <div className="min-h-screen bg-bg text-fg">
      <header className="border-b border-line">
        <div className="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-5">
          <p className="font-mono text-xs tracking-widest text-muted">16 × 12 ROPE</p>
          <h1 className="text-2xl font-medium tracking-tight">Core Rope</h1>
          <p className="max-w-xl text-sm leading-6 text-muted">
            A word line threads through a sense core for a one, and around it for a zero. Fetch
            reads that rope. A store writes only shadow RAM.
          </p>
        </div>
      </header>
      <main className="mx-auto grid w-full max-w-6xl gap-4 px-4 py-4 lg:grid-cols-5">
        <div className="order-2 flex min-w-0 flex-col gap-4 lg:order-1 lg:col-span-2">
          <Panel kicker="SOURCE" title="Assembly">
            <label className="block">
              <span className="font-mono text-xs tracking-widest text-muted">PROGRAM</span>
              <select
                className="mt-2 h-11 w-full border border-line bg-bg px-3 font-mono text-base text-fg"
                value={state.exampleId}
                onChange={(event) => {
                  const id = event.target.value;
                  if (id === "custom") return;
                  const next = EXAMPLES.find((item) => item.id === id);
                  if (next) dispatch({ type: "load", id: next.id, source: next.source });
                }}
              >
                {state.exampleId === "custom" ? <option value="custom">Custom</option> : null}
                {EXAMPLES.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
            <p className="mt-2 text-sm leading-6 text-muted">
              {example?.note ?? "Editing the source reseats the map and returns the machine to word 00."}
            </p>
            <label className="mt-4 block">
              <span className="sr-only">Assembly source</span>
              <textarea
                value={state.source}
                onChange={(event) => dispatch({ type: "source", source: event.target.value })}
                spellCheck={false}
                autoCapitalize="off"
                autoCorrect="off"
                autoComplete="off"
                className="min-h-56 w-full resize-y border border-line bg-bg p-3 font-mono text-base leading-6 text-fg"
              />
            </label>
            {error ? (
              <p role="alert" className="mt-3 border border-copper px-3 py-2 font-mono text-sm text-copper">
                {error}
              </p>
            ) : null}
            {image ? (
              <ol className="mt-4 border border-line" aria-label="Listing">
                {image.listing.map((line) => (
                  <li
                    key={line.address}
                    className={
                      "flex items-baseline gap-3 border-b border-line px-3 py-1 font-mono text-xs last:border-b-0 " +
                      (machine?.pc === line.address ? "bg-raised text-fg " : "") +
                      (line.origin === "pad" ? "text-muted" : "text-fg")
                    }
                  >
                    <span className="w-8 shrink-0 text-muted">{hex2(line.address)}</span>
                    <span className="w-10 shrink-0">{line.hex}</span>
                    <span className="min-w-0 truncate">
                      {line.labels.length > 0 ? `${line.labels.join(", ")}: ` : ""}
                      {line.mnemonic}
                    </span>
                  </li>
                ))}
              </ol>
            ) : null}
          </Panel>
          <Panel kicker="ISA" title="Twelve-bit word">
            <p className="text-sm leading-6 text-muted">
              Upper four bits are the opcode. The low eight bits are the operand, and only addresses
              0–15 are legal. Unallocated words read as NOP.
            </p>
            <table className="mt-3 w-full text-left">
              <caption className="sr-only">Instruction set</caption>
              <thead>
                <tr className="font-mono text-xs text-muted">
                  <th className="py-2 pr-3 font-medium">Op</th>
                  <th className="py-2 pr-3 font-medium">Code</th>
                  <th className="py-2 font-medium">Effect</th>
                </tr>
              </thead>
              <tbody>
                {ISA.map(([op, code, effect]) => (
                  <tr key={op} className="border-t border-line align-top">
                    <th className="py-2 pr-3 font-mono text-xs font-medium">{op}</th>
                    <td className="py-2 pr-3 font-mono text-xs text-muted">{code}</td>
                    <td className="py-2 text-sm leading-6 text-muted">{effect}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Panel>
        </div>
        <div className="order-1 flex min-w-0 flex-col gap-4 lg:order-2 lg:col-span-3">
          <Panel kicker="MACHINE" title="Accumulator">
            <dl className="grid grid-cols-2 gap-px bg-line sm:grid-cols-4">
              <Readout k="Map" v={image ? "OK" : "Open"} sub={image ? `SUM ${hex3(image.checksum)}` : "Fix source"} />
              <Readout
                k="Phase"
                v={phaseOf(machine, error)}
                sub={machine ? `${machine.trace.length} fetches` : "—"}
              />
              <Readout k="ACC" v={machine ? hex3(machine.acc) : "—"} sub={machine ? `${machine.acc} decimal` : "—"} />
              <Readout k="PC" v={machine ? hex2(machine.pc) : "—"} sub={pcLine?.mnemonic ?? "—"} />
            </dl>
            <p
              className={
                "mt-3 text-sm leading-6 " + (error || machine?.fault ? "text-copper" : "text-muted")
              }
            >
              {outcome(machine, error)}
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
              <ControlButton disabled={blocked} onClick={() => dispatch({ type: "pulse" })}>
                Pulse
              </ControlButton>
              <ControlButton
                disabled={blocked || Boolean(machine?.halted || machine?.fault)}
                onClick={() => dispatch({ type: "step" })}
              >
                Step
              </ControlButton>
              <ControlButton primary disabled={blocked} onClick={() => dispatch({ type: "run" })}>
                Run
              </ControlButton>
              <ControlButton disabled={blocked} onClick={() => dispatch({ type: "reset" })}>
                Reset
              </ControlButton>
            </div>
          </Panel>
          <Panel kicker="LOOM" title="Sense cores" aside={image ? "THROUGH 1 · AROUND 0" : undefined}>
            {image ? (
              <Loom
                image={image}
                selected={state.selected}
                pc={machine?.pc ?? null}
                sense={state.sense}
                senseFrom={state.senseFrom}
                onSelect={(address) => dispatch({ type: "select", address })}
              />
            ) : (
              <p className="text-sm leading-6 text-muted">The rope is open. Fix the source to seat a map.</p>
            )}
          </Panel>
          <Panel kicker="MEMORY" title="Shadow against rope">
            {image && machine ? (
              <div className="grid grid-cols-4 gap-2 sm:grid-cols-8">
                {machine.ram.map((word, address) => {
                  const rope = machine.rom[address] ?? 0;
                  const dirty = word !== rope;
                  const listed = image.listing[address];
                  const isPc = machine.pc === address;
                  return (
                    <button
                      key={address}
                      type="button"
                      onClick={() => dispatch({ type: "select", address })}
                      className={
                        "min-h-16 border px-2 py-2 text-left " +
                        (state.selected === address ? "border-copper " : "border-line ") +
                        (isPc ? "bg-raised" : "bg-bg")
                      }
                    >
                      <span className="flex items-center justify-between font-mono text-xs text-muted">
                        <span>{hex2(address)}</span>
                        {isPc ? <span className="text-copper">PC</span> : null}
                      </span>
                      <span className="mt-1 block font-mono text-sm tabular-nums">{hex3(word)}</span>
                      {dirty ? (
                        <span className="block truncate font-mono text-xs text-copper">rope {hex3(rope)}</span>
                      ) : (
                        <span className="block truncate font-mono text-xs text-muted">
                          {listed?.mnemonic ?? ""}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            ) : (
              <p className="text-sm text-muted">No image.</p>
            )}
          </Panel>
          <Panel kicker="TRACE" title="Fetches">
            {machine && machine.trace.length > 0 && image ? (
              <ol className="max-h-80 overflow-y-auto">
                {machine.trace.map((entry, index) => (
                  <li
                    key={`${entry.pc}-${index}`}
                    className="flex gap-3 border-b border-line py-2 font-mono text-xs last:border-b-0"
                  >
                    <span className="w-8 shrink-0 text-muted">{hex2(entry.pc)}</span>
                    <span className="w-10 shrink-0">{hex3(entry.word)}</span>
                    <span className="min-w-0">
                      <span>{mnemonic(entry.op, entry.addr, image.labels)}</span>
                      <span className="text-muted">
                        {" "}
                        ACC {hex3(entry.accBefore)}→{hex3(entry.accAfter)}
                        {entry.write
                          ? ` RAM ${hex2(entry.write.address)}←${hex3(entry.write.value)}`
                          : ""}
                        {entry.halted ? " halt" : ""}
                      </span>
                    </span>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="text-sm text-muted">No fetches yet.</p>
            )}
          </Panel>
        </div>
      </main>
      <footer className="mx-auto max-w-6xl px-4 pt-2 pb-10">
        <details className="border border-line">
          <summary className="min-h-11 cursor-pointer px-4 py-3 text-sm">Bring-up notes</summary>
          <div className="border-t border-line px-4 py-3 text-sm leading-6 text-muted">
            <p>
              This is a routing map, not a measured transformer, and not an Apollo Guidance Computer.
              Before any coil is built, prove one sense core and two word lines on a scope: one
              threaded through, one around. Set drive current, pulse width, and the comparator
              threshold from that jig and the core datasheet. Then expand to twelve planes and
              sixteen lines. Patterns 000, FFF, AAA, 555, walking ones, and walking zeros should
              match the hex image for a thousand clean sweeps before a controller is attached.
            </p>
            <p className="mt-3">
              Do not tie an unvalidated inductive load to a microcontroller pin. Use a current-limited
              driver, a planned return path, and flyback protection.
            </p>
          </div>
        </details>
        <p className="mt-4 text-sm text-muted">
          GNU Affero General Public License, version 3 or any later version.
        </p>
      </footer>
    </div>
  );
}

function Readout({ k, v, sub }: { k: string; v: string; sub?: string }) {
  return (
    <div className="min-w-0 bg-surface px-3 py-3">
      <dt className="font-mono text-xs tracking-widest text-muted">{k}</dt>
      <dd className="mt-1 truncate font-mono text-lg tabular-nums">{v}</dd>
      {sub ? <p className="truncate font-mono text-xs text-muted">{sub}</p> : null}
    </div>
  );
}
