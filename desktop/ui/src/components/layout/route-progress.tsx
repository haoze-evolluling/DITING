import { useEffect, useState } from "react";

type Phase = "idle" | "waiting" | "visible" | "leaving";

/** 延迟出现，避免预取命中时进度条一闪而过。 */
const START_DELAY_MS = 120;
/** 一旦出现至少停留该时长，避免「出现即消失」。 */
const MIN_VISIBLE_MS = 280;
/** 完成后的淡出时长，与 CSS transition 保持一致。 */
const LEAVE_MS = 200;

let phase: Phase = "idle";
let timer: number | undefined;
let shownAt = 0;
const subscribers = new Set<() => void>();

function setPhase(next: Phase) {
  phase = next;
  subscribers.forEach((notify) => notify());
}

function clearTimer() {
  if (timer !== undefined) {
    window.clearTimeout(timer);
    timer = undefined;
  }
}

/** 路由 chunk 开始加载：进入等待阶段，超过延迟后再显示进度条。 */
export function startRouteProgress() {
  clearTimer();
  if (phase === "visible" || phase === "leaving") return;
  setPhase("waiting");
  timer = window.setTimeout(() => {
    timer = undefined;
    shownAt = performance.now();
    setPhase("visible");
  }, START_DELAY_MS);
}

/** 路由内容就绪：满足最短展示时间后淡出并复位。 */
export function finishRouteProgress() {
  if (phase === "idle" || phase === "leaving") return;
  clearTimer();
  if (phase === "waiting") {
    setPhase("idle");
    return;
  }
  const remaining = shownAt + MIN_VISIBLE_MS - performance.now();
  timer = window.setTimeout(() => {
    setPhase("leaving");
    timer = window.setTimeout(() => {
      timer = undefined;
      setPhase("idle");
    }, LEAVE_MS);
  }, Math.max(remaining, 0));
}

/** 顶部细进度条：不确定进度，仅在路由 chunk 加载时出现。 */
export function RouteProgress() {
  const [current, setCurrent] = useState<Phase>(phase);

  useEffect(() => {
    const notify = () => setCurrent(phase);
    subscribers.add(notify);
    notify();
    return () => {
      subscribers.delete(notify);
    };
  }, []);

  if (current === "idle" || current === "waiting") return null;

  return (
    <div
      role="progressbar"
      aria-label="页面加载中"
      aria-valuetext="加载中"
      className={
        "pointer-events-none fixed inset-x-0 top-0 z-50 h-0.5 overflow-hidden transition-opacity duration-200 " +
        (current === "leaving" ? "opacity-0" : "opacity-100")
      }
    >
      <div className="route-progress-bar h-full" />
    </div>
  );
}
