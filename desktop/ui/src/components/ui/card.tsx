import type { HTMLAttributes, ReactNode } from "react";

import { cn } from "../../lib/cn";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "min-w-0 rounded-2xl border border-border bg-surface shadow-[var(--shadow-card)]",
        className,
      )}
      {...props}
    />
  );
}

interface CardHeaderProps extends Omit<HTMLAttributes<HTMLDivElement>, "title"> {
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}

export function CardHeader({
  title,
  description,
  actions,
  className,
  ...props
}: CardHeaderProps) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-5 pt-4",
        className,
      )}
      {...props}
    >
      <div className="min-w-0 flex-1">
        <h3 className="text-[14px] font-semibold tracking-[-0.01em] text-text">{title}</h3>
        {description ? (
          <p className="mt-0.5 text-[12px] leading-5 text-text-3">{description}</p>
        ) : null}
      </div>
      {actions ? (
        <div className="ml-auto flex shrink-0 flex-wrap items-center gap-2">{actions}</div>
      ) : null}
    </div>
  );
}

export function CardContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("min-w-0 px-5 py-4", className)} {...props} />;
}

export function CardFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-t border-border px-5 py-3",
        className,
      )}
      {...props}
    />
  );
}
