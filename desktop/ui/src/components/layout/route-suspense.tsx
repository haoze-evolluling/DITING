import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type MutableRefObject,
  type ReactNode,
} from "react";
import { AnimatePresence, m } from "motion/react";

import { MOTION_EASE_OUT, useMotion } from "../../hooks/use-motion";
import { RouteSkeleton } from "../skeletons/route-skeleton";

/** 加载超过该时长才显示骨架，避免预取命中时骨架一闪而过。 */
const SKELETON_DELAY_MS = 120;
/** 骨架一旦出现至少停留该时长，避免「出现即消失」造成闪烁。 */
const SKELETON_MIN_MS = 320;
/** 骨架淡出与内容淡入的交叉时长。 */
const CROSSFADE_SECONDS = 0.14;

/**
 * 等待骨架最短展示时间。Suspense 的 fallback 会在 content 就绪时立即卸载，
 * 因此由内容侧的包装组件继续显示骨架，直到满足最短时长后再交叉淡化。
 */
function MinimumHold({
  skeleton,
  shownAtRef,
  onContentMount,
  children,
}: {
  skeleton: ReactNode;
  shownAtRef: MutableRefObject<number | null>;
  onContentMount: () => void;
  children: ReactNode;
}) {
  const { allowPageEnter } = useMotion();
  // 内容在 120ms 内就绪时骨架从未出现，直接渲染内容。
  const [ready, setReady] = useState(() => shownAtRef.current === null);

  useEffect(() => {
    onContentMount();
    if (shownAtRef.current === null) {
      setReady(true);
      return;
    }
    const remaining = shownAtRef.current + SKELETON_MIN_MS - performance.now();
    if (remaining <= 0) {
      setReady(true);
      return;
    }
    const timer = window.setTimeout(() => setReady(true), remaining);
    return () => window.clearTimeout(timer);
  }, [onContentMount, shownAtRef]);

  if (!allowPageEnter) {
    return (
      <div className="relative">
        <div className={ready ? undefined : "invisible"} inert={!ready}>
          {children}
        </div>
        {ready ? null : (
          <div className="pointer-events-none absolute inset-x-0 top-0">{skeleton}</div>
        )}
      </div>
    );
  }

  const showSkeleton = !ready && shownAtRef.current !== null;

  return (
    <div className="relative">
      <m.div
        initial={false}
        animate={{ opacity: ready ? 1 : 0 }}
        transition={{
          duration: ready ? CROSSFADE_SECONDS : 0,
          ease: MOTION_EASE_OUT,
        }}
        inert={!ready}
      >
        {children}
      </m.div>
      <AnimatePresence initial={false}>
        {showSkeleton ? (
          <m.div
            key="route-skeleton"
            initial={{ opacity: 1 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.12, ease: MOTION_EASE_OUT }}
            className="pointer-events-none absolute inset-x-0 top-0"
          >
            {skeleton}
          </m.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}

/**
 * 路由级 Suspense：按当前路径渲染对应骨架，并应用「延迟显示 + 最短展示」策略。
 * 该组件以路径为 key 挂载，计时与骨架状态随路由切换自动重置。
 */
export function PageSuspense({
  pathname,
  children,
}: {
  pathname: string;
  children: ReactNode;
}) {
  const skeleton = useMemo(() => <RouteSkeleton pathname={pathname} />, [pathname]);
  const shownAtRef = useRef<number | null>(null);
  const timerRef = useRef<number | null>(null);
  const [skeletonVisible, setSkeletonVisible] = useState(false);

  useEffect(() => {
    timerRef.current = window.setTimeout(() => {
      timerRef.current = null;
      shownAtRef.current = performance.now();
      setSkeletonVisible(true);
    }, SKELETON_DELAY_MS);
    return () => {
      if (timerRef.current !== null) {
        window.clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
  }, []);

  const handleContentMount = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  return (
    <Suspense fallback={skeletonVisible ? skeleton : null}>
      <MinimumHold
        skeleton={skeleton}
        shownAtRef={shownAtRef}
        onContentMount={handleContentMount}
      >
        {children}
      </MinimumHold>
    </Suspense>
  );
}
