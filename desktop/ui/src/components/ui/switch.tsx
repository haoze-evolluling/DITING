import * as SwitchPrimitive from "@radix-ui/react-switch";

import { cn } from "../../lib/cn";

interface SwitchProps {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  disabled?: boolean;
  label?: string;
  className?: string;
}

export function Switch({ checked, onCheckedChange, disabled, label, className }: SwitchProps) {
  return (
    <SwitchPrimitive.Root
      checked={checked}
      onCheckedChange={onCheckedChange}
      disabled={disabled}
      aria-label={label}
      className={cn(
        "relative inline-flex h-[22px] w-[38px] shrink-0 cursor-pointer items-center rounded-full border border-transparent bg-surface-3 transition-colors data-[state=checked]:bg-accent disabled:cursor-not-allowed disabled:opacity-40",
        className,
      )}
    >
      <SwitchPrimitive.Thumb className="motion-switch-thumb block h-[18px] w-[18px] translate-x-[2px] rounded-full bg-white shadow-sm data-[state=checked]:translate-x-[18px]" />
    </SwitchPrimitive.Root>
  );
}
