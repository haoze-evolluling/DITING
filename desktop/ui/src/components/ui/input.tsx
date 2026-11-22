import * as React from "react";

import { cn } from "../../lib/cn";

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, leading, trailing, ...props }, ref) => {
    if (!leading && !trailing) {
      return (
        <input
          ref={ref}
          className={cn(
            "h-9 w-full min-w-0 rounded-lg border border-border bg-surface-2 px-3 text-[13px] text-text placeholder:text-text-3 transition-colors hover:border-border-strong focus:border-accent focus:bg-surface focus:outline-none",
            className,
          )}
          {...props}
        />
      );
    }
    return (
      <div
        className={cn(
          "flex h-9 w-full min-w-0 items-center gap-2 rounded-lg border border-border bg-surface-2 px-3 transition-colors focus-within:border-accent focus-within:bg-surface hover:border-border-strong",
          className,
        )}
      >
        {leading ? <span className="text-text-3">{leading}</span> : null}
        <input
          ref={ref}
          className="min-w-0 flex-1 bg-transparent text-[13px] text-text outline-none placeholder:text-text-3"
          {...props}
        />
        {trailing ? <span className="flex items-center text-text-3">{trailing}</span> : null}
      </div>
    );
  },
);
Input.displayName = "Input";
