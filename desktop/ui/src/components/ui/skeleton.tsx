import { cn } from "../../lib/cn";

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("motion-skeleton rounded-lg bg-surface-3", className)} />;
}
