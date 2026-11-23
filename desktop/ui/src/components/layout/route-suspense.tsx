import { Suspense, useEffect, type ReactNode } from "react";

import { finishRouteProgress, startRouteProgress } from "./route-progress";

/**
 * 路由 Suspense：加载期间只展示顶部进度条，不再绘制整页骨架。
 * 占位块保留最小高度，减少页面从空到有内容时的整体高度跳变。
 */
function RouteFallback() {
  useEffect(() => {
    startRouteProgress();
    // 提前离开（取消导航、退出登录）时也要结束进度条，避免残留。
    return () => finishRouteProgress();
  }, []);
  return <div className="min-h-[320px]" aria-hidden />;
}

/** 内容已解除挂起：通知进度条完成。 */
function RouteReady() {
  useEffect(() => {
    finishRouteProgress();
  }, []);
  return null;
}

export function PageSuspense({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<RouteFallback />}>
      {children}
      <RouteReady />
    </Suspense>
  );
}
