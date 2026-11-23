import { Loader2 } from "lucide-react";

import { cn } from "../../lib/cn";

/**
 * 局部加载状态：卡片外壳、标题与操作区保持可见，仅数据区显示轻量指示。
 * 默认高度对齐常见卡片内容区，避免数据就绪后布局明显跳动。
 */
export function LoadingState({
  label = "正在加载…",
  className,
}: {
  label?: string;
  className?: string;
}) {
  return (
    <div
      role="status"
      aria-live="polite"
      aria-label={label}
      className={cn(
        "flex min-h-[140px] flex-1 flex-col items-center justify-center gap-2 text-text-3",
        className,
      )}
    >
      <Loader2 aria-hidden className="motion-spinner h-4 w-4" />
      <span className="text-[12px]">{label}</span>
    </div>
  );
}

/** 行内加载指示：用于数值、紧凑行或不便放置文案的位置。 */
export function InlineLoading({ className }: { className?: string }) {
  return (
    <Loader2 aria-hidden className={cn("motion-spinner h-3.5 w-3.5 text-text-3", className)} />
  );
}
