import type { ButtonHTMLAttributes, ReactNode } from "react";

export function Panel({
  kicker,
  title,
  aside,
  children,
}: {
  kicker: string;
  title: string;
  aside?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="min-w-0 border border-line bg-surface">
      <header className="flex items-end justify-between gap-3 border-b border-line px-4 py-3">
        <div className="min-w-0">
          <p className="font-mono text-xs tracking-widest text-muted">{kicker}</p>
          <h2 className="mt-1 text-base font-medium">{title}</h2>
        </div>
        {aside ? <div className="shrink-0 font-mono text-xs text-muted">{aside}</div> : null}
      </header>
      <div className="p-4">{children}</div>
    </section>
  );
}

export function ControlButton({
  primary = false,
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { primary?: boolean }) {
  return (
    <button
      {...props}
      type="button"
      className={
        "inline-flex h-11 w-full items-center justify-center border px-3 text-sm " +
        (primary
          ? "border-copper bg-copper text-ink disabled:border-line disabled:bg-surface disabled:text-muted"
          : "border-line bg-bg text-fg disabled:text-muted") +
        (className ? ` ${className}` : "")
      }
    />
  );
}
