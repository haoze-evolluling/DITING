import type { ReactNode } from "react";

export function InfoRow({
  label,
  children,
  mono = false,
}: {
  label: string;
  children: ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex min-w-0 items-start justify-between gap-4 border-b border-border/60 py-2 last:border-b-0">
      <span className="shrink-0 text-[11.5px] text-text-3">{label}</span>
      <span
        className={
          mono
            ? "mono min-w-0 break-all text-right text-[11px] text-text-2"
            : "min-w-0 break-words text-right text-[12px] text-text-2"
        }
      >
        {children}
      </span>
    </div>
  );
}
