import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

import { cn } from "../../lib/cn";
import { Card } from "./card";
import { Skeleton } from "./skeleton";

type Tone = "accent" | "good" | "danger" | "violet" | "neutral";

const toneStyles: Record<Tone, { icon: string; bar: string }> = {
  accent: { icon: "bg-accent-soft text-accent", bar: "bg-accent" },
  good: { icon: "bg-good-soft text-good", bar: "bg-good" },
  danger: { icon: "bg-danger-soft text-danger", bar: "bg-danger" },
  violet: { icon: "bg-violet-soft text-violet", bar: "bg-violet" },
  neutral: { icon: "bg-surface-3 text-text-2", bar: "bg-text-3" },
};

export function StatTile({
  label,
  value,
  hint,
  icon: Icon,
  tone = "neutral",
  loading = false,
  className,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  icon: LucideIcon;
  tone?: Tone;
  loading?: boolean;
  className?: string;
}) {
  const styles = toneStyles[tone];
  return (
    <Card className={cn("relative overflow-hidden px-4 py-3.5", className)}>
      <span className={cn("absolute left-0 top-4 h-6 w-0.5 rounded-r-full", styles.bar)} />
      <div className="flex min-w-0 items-center justify-between gap-3">
        <span className="min-w-0 truncate text-[12px] text-text-3">{label}</span>
        <span
          className={cn(
            "flex h-7 w-7 shrink-0 items-center justify-center rounded-lg",
            styles.icon,
          )}
        >
          <Icon className="h-3.5 w-3.5" />
        </span>
      </div>
      {loading ? (
        <Skeleton className="mt-3 h-7 w-24" />
      ) : (
        <div className="mt-2.5 truncate text-[25px] font-semibold leading-7 tracking-[-0.03em] text-text">
          {value}
        </div>
      )}
      <div className="mt-1 min-h-[16px] break-words text-[11.5px] leading-4 text-text-3">{hint}</div>
    </Card>
  );
}
