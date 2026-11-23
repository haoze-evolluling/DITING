import { Suspense, useRef } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { m } from "motion/react";
import { Outlet, useLocation } from "react-router-dom";

import { useStatus } from "../../hooks/use-api";
import { MOTION_EASE_OUT, useMotion } from "../../hooks/use-motion";
import { describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import { Button } from "../ui/button";
import { PageFallback } from "./page-fallback";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";

function ConnectionBanner() {
  const status = useStatus();
  const { allowPageEnter } = useMotion();
  if (!status.error) return null;

  const content = (
    <>
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
    </>
  );

  const className =
    "flex flex-wrap items-center gap-2 border-b border-warn/25 bg-warn-soft px-5 py-2 text-[12px] text-warn";

  if (!allowPageEnter) {
    return <div className={className}>{content}</div>;
  }

  return (
    <m.div
      initial={{ opacity: 0, y: -6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.18, ease: MOTION_EASE_OUT }}
      className={className}
    >
      {content}
    </m.div>
  );
}

export function AppShell() {
  const location = useLocation();
  const { allowPageEnter, allowStagger, isRich, pageDuration } = useMotion();
  const routeMotionRef = useRef({
    path: location.pathname,
    stagger: allowStagger,
  });

  if (routeMotionRef.current.path !== location.pathname) {
    routeMotionRef.current = {
      path: location.pathname,
      stagger: allowStagger,
    };
  }

  const staggerThisRoute = routeMotionRef.current.stagger && allowStagger;

  return (
    <div className="flex h-full bg-bg">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <ConnectionBanner />
        <main className="app-canvas min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-[1480px] px-5 py-5 lg:px-7 lg:py-6">
            {allowPageEnter ? (
              <m.div
                key={location.pathname}
                initial={{ opacity: 0, y: isRich ? 10 : 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: pageDuration, ease: MOTION_EASE_OUT }}
                className={cn(staggerThisRoute && "motion-stagger")}
              >
                <Suspense fallback={<PageFallback />}>
                  <Outlet />
                </Suspense>
              </m.div>
            ) : (
              <div key={location.pathname}>
                <Suspense fallback={<PageFallback />}>
                  <Outlet />
                </Suspense>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
