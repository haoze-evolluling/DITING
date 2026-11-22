import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
}: {
  icon: LucideIcon;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-12 text-center">
      <div className="mb-3 flex h-11 w-11 items-center justify-center rounded-2xl bg-surface-3 text-text-3">
        <Icon className="h-5 w-5" />
      </div>
      <p className="text-[13.5px] font-medium text-text">{title}</p>
      {description ? (
        <p className="mt-1 max-w-[360px] text-[12px] leading-5 text-text-3">{description}</p>
      ) : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
