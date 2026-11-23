import { Suspense, useEffect, useRef, useState } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { AnimatePresence, m } from "motion/react";
import { useLocation, useOutlet } from "react-router-dom";

import { useStatus } from "../../hooks/use-api";
import { MOTION_EASE_OUT, useMotion } from "../../hooks/use-motion";
import { describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import { Button } from "../ui/button";
import { Collapse } from "../ui/swap";
import { PageFallback } from "./page-fallback";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";

/** 内容淡入时长：兜住懒加载 chunk 就绪后「骨架 → 内容」的硬切。 */
const CONTENT_FADE = 0.14;

function ConnectionBanner() {
  const status = useStatus();

  return (
    <Collapse show={Boolean(status.error)}>
      <div className="flex flex-wrap items-center gap-2 border-b border-warn/25 bg-warn-soft px-5 py-2 text-[12px] text-warn">
        <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
        <span className="min-w-0 flex-1">{describeError(status.error)}</span>
        <Button
          size="sm"
          variant="ghost"
          className="text-warn hover:bg-warn/10 hover:text-warn"
          onClick={() => void status.refetch()}
        >
          <RefreshCw className="h-3.5 w-3.5" />
          重试
        </Button>
      </div>
    </Collapse>
  );
}

/**
 * 冻结本实例首次渲染时拿到的路由元素。
 * React Router 的 context 是实时的，若不冻结，退场中的旧页面会被渲染成新页面。
 * 该组件以 pathname 为 key 挂载，因此每个路由实例只持有自己的 outlet。
 */
function FrozenOutlet() {
  const element = useOutlet();
  const [node] = useState(element);
  return <>{node}</>;
}

export function AppShell() {
  const location = useLocation();
  const mainRef = useRef<HTMLElement | null>(null);
  const { allowPageEnter, allowStagger, isRich, pageDuration, pageExitDuration } = useMotion();
  const [routeState, setRouteState] = useState({
    path: location.pathname,
    stagger: allowStagger,
  });

  // 派生状态：仅在路由真正变化时记录当时的错峰资格，
  // 避免动画档位切换导致当前页面卡片重播入场。
  if (routeState.path !== location.pathname) {
    setRouteState({ path: location.pathname, stagger: allowStagger });
  }

  const staggerThisRoute = allowStagger && routeState.stagger;

  const scrollToTop = () => {
    mainRef.current?.scrollTo({ top: 0 });
  };

  // 无页面动效的档位没有退场回调，直接随路由重置滚动位置。
  useEffect(() => {
    if (!allowPageEnter) scrollToTop();
  }, [location.pathname, allowPageEnter]);

  return (
    <div className="flex h-full bg-bg">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <ConnectionBanner />
        <main ref={mainRef} className="app-canvas min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-[1480px] px-5 py-5 lg:px-7 lg:py-6">
            {allowPageEnter ? (
              <AnimatePresence mode="wait" initial={false} onExitComplete={scrollToTop}>
                <m.div
                  key={location.pathname}
                  initial={{ opacity: 0, y: staggerThisRoute ? 0 : isRich ? 10 : 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{
                    opacity: 0,
                    y: isRich ? -4 : -2,
                    transition: { duration: pageExitDuration, ease: MOTION_EASE_OUT },
                  }}
                  transition={{ duration: pageDuration, ease: MOTION_EASE_OUT }}
                  className={cn(staggerThisRoute && "motion-stagger")}
                >
                  <Suspense fallback={<PageFallback />}>
                    <m.div
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ duration: CONTENT_FADE, ease: MOTION_EASE_OUT }}
                    >
                      <FrozenOutlet />
                    </m.div>
                  </Suspense>
                </m.div>
              </AnimatePresence>
            ) : (
              <div key={location.pathname}>
                <Suspense fallback={<PageFallback />}>
                  <FrozenOutlet />
                </Suspense>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
