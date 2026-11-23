import { useId } from "react";
import type { LucideIcon } from "lucide-react";
import { m } from "motion/react";

import { MOTION_SPRING_SNAPPY, useMotion } from "../../hooks/use-motion";
import { cn } from "../../lib/cn";

export interface SegmentOption<T extends string> {
  value: T;
  label: string;
  icon?: LucideIcon;
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  className,
}: {
  value: T;
  options: SegmentOption<T>[];
  onChange: (value: T) => void;
  className?: string;
}) {
  const groupId = useId();
  const { allowLayout } = useMotion();

  return (
    <div
      role="radiogroup"
      className={cn(
        "inline-flex items-center gap-0.5 rounded-lg border border-border bg-surface-2 p-0.5",
        className,
      )}
    >
      {options.map((option) => {
        const active = option.value === value;
        const Icon = option.icon;
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(option.value)}
            className={cn(
              "relative inline-flex h-7 items-center gap-1.5 rounded-md px-2.5 text-[12px] font-medium transition-colors",
              active ? "text-text" : "text-text-3 hover:text-text",
            )}
          >
            {active ? (
              allowLayout ? (
                <m.span
                  layoutId={`segmented-${groupId}`}
                  transition={MOTION_SPRING_SNAPPY}
                  aria-hidden
                  className="pointer-events-none absolute inset-0 rounded-md bg-surface shadow-sm"
                />
              ) : (
                <span
                  aria-hidden
                  className="pointer-events-none absolute inset-0 rounded-md bg-surface shadow-sm"
                />
              )
            ) : null}
            {Icon ? <Icon className="relative z-[1] h-3.5 w-3.5" /> : null}
            <span className="relative z-[1]">{option.label}</span>
          </button>
        );
      })}
    </div>
  );
}
