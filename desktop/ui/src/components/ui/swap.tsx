import type { ReactNode } from "react";
import { AnimatePresence, m } from "motion/react";

import { MOTION_EASE_OUT, useMotion } from "../../hooks/use-motion";
import { cn } from "../../lib/cn";

/**
 * 同一区域内两种状态的交叉淡化（图表/表格、骨架/表单等）。
 * 低档位或不支持页面动效时退化为直接替换，不产生任何动画开销。
 */
export function Swap({
  swapKey,
  children,
  className,
  durationMs = 140,
}: {
  swapKey: string;
  children: ReactNode;
  className?: string;
  durationMs?: number;
}) {
  const { allowPageEnter } = useMotion();

  if (!allowPageEnter) {
    return <div className={className}>{children}</div>;
  }

  return (
    <AnimatePresence mode="wait" initial={false}>
      <m.div
        key={swapKey}
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -4 }}
        transition={{ duration: durationMs / 1000, ease: MOTION_EASE_OUT }}
        className={className}
      >
        {children}
      </m.div>
    </AnimatePresence>
  );
}

/**
 * 显示/隐藏一块内容（错误提示、连接异常横幅）。
 * 隐藏时不渲染任何节点，避免空占位破坏 flex / space-y 间距。
 */
export function Collapse({
  show,
  children,
  className,
}: {
  show: boolean;
  children: ReactNode;
  className?: string;
}) {
  const { allowPageEnter } = useMotion();

  if (!allowPageEnter) {
    return show ? <>{children}</> : null;
  }

  return (
    <AnimatePresence initial={false}>
      {show ? (
        <m.div
          key="collapse"
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          exit={{ opacity: 0, height: 0 }}
          transition={{ duration: 0.16, ease: MOTION_EASE_OUT }}
          className={cn("overflow-hidden", className)}
        >
          {children}
        </m.div>
      ) : null}
    </AnimatePresence>
  );
}
