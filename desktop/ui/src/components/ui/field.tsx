import type { ReactNode, TextareaHTMLAttributes } from "react";

import { cn } from "../../lib/cn";

export function Field({
  label,
  hint,
  children,
  className,
}: {
  label: string;
  hint?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <label className={cn("block", className)}>
      <span className="text-[12px] text-text">{label}</span>
      <div className="mt-1.5">{children}</div>
      {hint ? <span className="mt-1 block text-[10.5px] text-text-3">{hint}</span> : null}
    </label>
  );
}

export function Textarea({
  className,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-[96px] w-full min-w-0 resize-y rounded-lg border border-border bg-surface-2 px-3 py-2 text-[12.5px] leading-6 text-text placeholder:text-text-3 transition-colors hover:border-border-strong focus:border-accent focus:bg-surface focus:outline-none",
        className,
      )}
      {...props}
    />
  );
}
