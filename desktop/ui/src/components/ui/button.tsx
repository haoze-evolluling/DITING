import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { Loader2 } from "lucide-react";

import { cn } from "../../lib/cn";

type Variant = "primary" | "secondary" | "ghost" | "danger" | "dangerSoft" | "success";
type Size = "sm" | "md" | "lg" | "icon";

const variants: Record<Variant, string> = {
  primary:
    "bg-accent text-accent-ink shadow-[0_1px_2px_rgba(10,30,60,0.14)] hover:bg-accent-hover",
  secondary: "border border-border bg-surface text-text hover:bg-surface-2",
  ghost: "text-text-2 hover:bg-surface-3 hover:text-text",
  danger: "bg-danger text-white hover:opacity-90",
  dangerSoft: "bg-danger-soft text-danger hover:opacity-85",
  success: "bg-good text-white hover:opacity-90",
};

const sizes: Record<Size, string> = {
  sm: "h-8 rounded-lg px-2.5 text-[12.5px]",
  md: "h-9 rounded-lg px-3.5 text-[13px]",
  lg: "h-10 rounded-xl px-4 text-[13.5px]",
  icon: "h-8 w-8 rounded-lg",
};

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  asChild?: boolean;
  loading?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant = "secondary",
      size = "md",
      asChild = false,
      loading = false,
      disabled,
      children,
      ...props
    },
    ref,
  ) => {
    const Component = asChild ? Slot : "button";
    return (
      <Component
        ref={ref}
        className={cn(
          "inline-flex select-none items-center justify-center gap-1.5 whitespace-nowrap font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:pointer-events-none disabled:opacity-50",
          variants[variant],
          sizes[size],
          className,
        )}
        disabled={disabled || loading}
        {...props}
      >
        {asChild ? (
          children
        ) : (
          <>
            {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
            {children}
          </>
        )}
      </Component>
    );
  },
);
Button.displayName = "Button";
