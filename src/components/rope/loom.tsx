import { threadSentence } from "@/lib/rope/assemble";
import type { Image } from "@/lib/rope/assemble";
import { hex2, hex3 } from "@/lib/rope/isa";
import { ControlButton } from "@/components/rope/ui";

export function Loom({
  image,
  selected,
  pc,
  sense,
  senseFrom,
  onSelect,
}: {
  image: Image;
  selected: number;
  pc: number | null;
  sense: number | null;
  senseFrom: number | null;
  onSelect: (address: number) => void;
}) {
  const row = image.rows[selected];
  const line = image.listing[selected];
  if (!row || !line) return null;
  const title = line.labels[0] ? `${line.labels[0]} ${hex2(selected)}` : `LINE ${hex2(selected)}`;

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <p className="min-w-0 truncate font-mono text-sm">{title}</p>
        <p className="shrink-0 font-mono text-xs text-muted sm:text-sm">
          {row.hex} · {row.binary}
        </p>
      </div>
      <Wire word={row.word} label={threadSentence(row)} />
      <p className="mt-3 text-sm leading-6 text-muted">{threadSentence(row)}</p>
      <div className="mt-4 grid grid-cols-2 gap-2">
        <ControlButton onClick={() => onSelect((selected + 15) % 16)}>Previous line</ControlButton>
        <ControlButton onClick={() => onSelect((selected + 1) % 16)}>Next line</ControlButton>
      </div>
      <SenseLatch sense={sense} senseFrom={senseFrom} />
      <ol className="mt-4 max-h-80 overflow-y-auto border border-line" aria-label="Word lines">
        {image.rows.map((item) => {
          const listed = image.listing[item.address];
          const bits = item.binary.split("");
          const isPc = pc === item.address;
          const isSel = selected === item.address;
          return (
            <li key={item.address}>
              <button
                type="button"
                aria-pressed={isSel}
                onClick={() => onSelect(item.address)}
                className={
                  "flex min-h-11 w-full items-center gap-2 border px-2 text-left " +
                  (isSel ? "border-copper" : "border-transparent") +
                  (isPc ? " bg-raised" : "")
                }
              >
                <span className="w-8 shrink-0 font-mono text-xs text-muted">{hex2(item.address)}</span>
                <span className="grid min-w-0 flex-1 grid-cols-12 gap-1" aria-hidden="true">
                  {bits.map((bit, index) => (
                    <span
                      key={`${item.address}-${index}`}
                      className={bit === "1" ? "h-2.5 bg-copper" : "h-2.5 border border-line"}
                    />
                  ))}
                </span>
                <span className="hidden w-14 shrink-0 truncate font-mono text-xs text-muted sm:block">
                  {listed?.labels[0] ?? ""}
                </span>
                <span className="w-10 shrink-0 text-right font-mono text-xs">{item.hex}</span>
                {isPc ? <span className="w-6 shrink-0 font-mono text-xs text-copper">PC</span> : null}
              </button>
            </li>
          );
        })}
      </ol>
      <details className="mt-4 border border-line">
        <summary className="min-h-11 cursor-pointer px-3 py-3 text-sm">Threading list</summary>
        <div className="border-t border-line px-3 py-3">
          <p className="text-sm leading-6 text-muted">
            Core 0 is the least significant bit. Through is a one. Around is a zero. Select one
            drive line at a time.
          </p>
          <ol className="mt-2">
            {image.rows.map((item) => (
              <li key={item.address} className="py-1 text-sm leading-6 text-muted">
                {threadSentence(item)}
              </li>
            ))}
          </ol>
        </div>
      </details>
    </div>
  );
}

function Wire({ word, label }: { word: number; label: string }) {
  const width = 360;
  const height = 104;
  const y = 44;
  const radius = 11;
  const left = 8;
  const right = 350;
  const pitch = (right - left) / 12;
  let path = `M ${left} ${y}`;
  const cores: { cx: number; bit: number; through: boolean }[] = [];
  for (let index = 0; index < 12; index += 1) {
    const bit = 11 - index;
    const through = (word & (1 << bit)) !== 0;
    const cx = left + (index + 0.5) * pitch;
    const x0 = cx - radius - 2;
    const x1 = cx + radius + 2;
    path += ` L ${x0.toFixed(2)} ${y}`;
    path += through
      ? ` L ${x1.toFixed(2)} ${y}`
      : ` Q ${cx.toFixed(2)} ${y + 42} ${x1.toFixed(2)} ${y}`;
    cores.push({ cx, bit, through });
  }
  path += ` L ${right} ${y}`;

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="mt-3 h-auto w-full" role="img" aria-label={label}>
      <title>{label}</title>
      <rect x="0" y={y - 5} width="8" height="10" fill="var(--color-copper)" />
      <path
        d={path}
        fill="none"
        stroke="var(--color-copper)"
        strokeWidth="2"
        strokeLinejoin="round"
        strokeLinecap="round"
      />
      {cores.map((core) => (
        <g key={core.bit}>
          <circle
            cx={core.cx}
            cy={y}
            r={radius}
            fill="none"
            stroke={core.through ? "var(--color-copper)" : "var(--color-line)"}
            strokeWidth={core.through ? 2.5 : 1.5}
          />
          <text
            x={core.cx}
            y="96"
            textAnchor="middle"
            fill="var(--color-muted)"
            fontSize="11"
            fontFamily="IBM Plex Mono, ui-monospace, monospace"
          >
            {core.bit}
          </text>
        </g>
      ))}
    </svg>
  );
}

function SenseLatch({ sense, senseFrom }: { sense: number | null; senseFrom: number | null }) {
  return (
    <div className="mt-4">
      <p className="font-mono text-xs tracking-widest text-muted">
        SENSE · CORE 11 AT LEFT
        {sense !== null && senseFrom !== null ? ` · LATCH ${hex3(sense)} FROM ${hex2(senseFrom)}` : ""}
      </p>
      <div className="mt-2 grid grid-cols-12 gap-1">
        {Array.from({ length: 12 }, (_, index) => {
          const bit = 11 - index;
          const known = sense !== null;
          const on = known && (sense & (1 << bit)) !== 0;
          return (
            <div
              key={bit}
              className={
                "flex h-8 items-center justify-center border font-mono text-xs " +
                (known && on ? "border-copper bg-copper text-ink" : "border-line text-muted")
              }
            >
              {known ? (on ? "1" : "0") : "–"}
            </div>
          );
        })}
      </div>
    </div>
  );
}
