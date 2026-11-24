import type { ReactNode } from "react";
import { CircleCheck, TriangleAlert } from "lucide-react";

import { cn } from "../../../lib/cn";

export function formatMs(value?: number | null): string {
  if (value === undefined || value === null || !Number.isFinite(value)) return "—";
  if (value === 0) return "0 ms";
  if (value < 1) return "<1 ms";
  return `${value < 10 ? value.toFixed(1) : value.toFixed(0)} ms`;
}

export function ResultError({ message }: { message: string }) {
  return (
    <div className="rounded-xl border border-danger/25 bg-danger-soft px-3.5 py-3 text-[12px] leading-5 text-danger">
      {message}
    </div>
  );
}

export function ResultNotice({
  tone = "neutral",
  children,
}: {
  tone?: "neutral" | "good" | "warn";
  children: ReactNode;
}) {
  const styles = {
    neutral: "border-border bg-surface-2 text-text-2",
    good: "border-good/25 bg-good-soft text-good",
    warn: "border-warn/25 bg-warn-soft text-warn",
  }[tone];
  return (
    <div className={cn("rounded-xl border px-3.5 py-2.5 text-[11.5px] leading-5", styles)}>
      {children}
    </div>
  );
}

export function StatusLine({
  ok,
  title,
  detail,
}: {
  ok: boolean;
  title: ReactNode;
  detail?: ReactNode;
}) {
  return (
    <div
      className={cn(
        "flex items-start gap-2.5 rounded-xl border px-3.5 py-3",
        ok ? "border-good/25 bg-good-soft" : "border-warn/25 bg-warn-soft",
      )}
    >
      {ok ? (
        <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-good" />
      ) : (
        <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-warn" />
      )}
      <div className="min-w-0">
        <div className={cn("text-[12.5px] font-medium", ok ? "text-good" : "text-warn")}>
          {title}
        </div>
        {detail ? (
          <div className="mt-0.5 text-[11.5px] leading-5 text-text-2">{detail}</div>
        ) : null}
      </div>
    </div>
  );
}

export function ResultTable({
  columns,
  children,
}: {
  columns: string[];
  children: ReactNode;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border">
      <div
        className="grid gap-3 bg-surface-2 px-3 py-1.5 text-[10.5px] text-text-3"
        style={{ gridTemplateColumns: gridTemplate(columns.length) }}
      >
        {columns.map((column) => (
          <span key={column}>{column}</span>
        ))}
      </div>
      {children}
    </div>
  );
}

function gridTemplate(count: number): string {
  switch (count) {
    case 2:
      return "1fr auto";
    case 3:
      return "64px 1fr auto";
    case 4:
      return "1.2fr 70px 60px 1.6fr";
    default:
      return `repeat(${count}, minmax(0, 1fr))`;
  }
}

export function EmptyHint({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-[96px] items-center justify-center rounded-xl border border-dashed border-border/80 px-4 text-center text-[11.5px] text-text-3">
      {children}
    </div>
  );
}
