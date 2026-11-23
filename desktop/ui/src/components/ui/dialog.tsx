import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import type { ReactNode } from "react";

import { cn } from "../../lib/cn";

export const Dialog = DialogPrimitive.Root;

export function DialogContent({
  className,
  children,
  showClose = true,
}: {
  className?: string;
  children: ReactNode;
  showClose?: boolean;
}) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Overlay className="motion-overlay fixed inset-0 z-50 bg-[rgba(6,14,26,0.46)] backdrop-blur-[2px]" />
      <DialogPrimitive.Content
        className={cn(
          "motion-dialog fixed left-1/2 top-1/2 z-50 max-h-[86vh] w-[min(560px,calc(100vw-40px))] -translate-x-1/2 -translate-y-1/2 overflow-y-auto rounded-2xl border border-border bg-surface p-0 shadow-[var(--shadow-pop)] focus:outline-none",
          className,
        )}
      >
        {children}
        {showClose ? (
          <DialogPrimitive.Close
            aria-label="关闭"
            className="absolute right-4 top-4 rounded-lg p-1 text-text-3 transition-colors hover:bg-surface-3 hover:text-text"
          >
            <X className="h-4 w-4" />
          </DialogPrimitive.Close>
        ) : null}
      </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
  );
}

export function DialogHeader({
  title,
  description,
  className,
}: {
  title: ReactNode;
  description?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("border-b border-border px-5 py-4 pr-12", className)}>
      <DialogPrimitive.Title className="text-[15px] font-semibold text-text">
        {title}
      </DialogPrimitive.Title>
      {description ? (
        <DialogPrimitive.Description className="mt-1 text-[12.5px] leading-5 text-text-3">
          {description}
        </DialogPrimitive.Description>
      ) : null}
    </div>
  );
}

export function DialogBody({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("px-5 py-4", className)}>{children}</div>;
}

export function DialogFooter({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div
      className={cn(
        "flex items-center justify-end gap-2 border-t border-border bg-surface-2 px-5 py-3",
        className,
      )}
    >
      {children}
    </div>
  );
}
