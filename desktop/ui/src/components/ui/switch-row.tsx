import type { ReactNode } from "react";

import { cn } from "../../lib/cn";
import { Switch } from "./switch";

export function SwitchRow({
  title,
  description,
  checked,
  onCheckedChange,
  disabled,
  className,
}: {
  title: ReactNode;
  description?: ReactNode;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex items-center justify-between gap-4 border-b border-border/60 py-2.5 last:border-b-0",
        className,
      )}
    >
      <div className="min-w-0">
        <div className="text-[12px] text-text">{title}</div>
        {description ? (
          <div className="mt-0.5 text-[10.5px] leading-4 text-text-3">{description}</div>
        ) : null}
      </div>
      <Switch
        checked={checked}
        onCheckedChange={onCheckedChange}
        disabled={disabled}
        label={typeof title === "string" ? title : undefined}
      />
    </div>
  );
}
