import { useEffect, useMemo, useRef, useState } from "react";

import { useUIStore, type MotionLevel } from "../stores/ui";

export interface MotionLevelOption {
  value: MotionLevel;
  label: string;
  summary: string;
  performance: string;
}

export const MOTION_LEVEL_OPTIONS: MotionLevelOption[] = [
  {
    value: "off",
    label: "关闭",
    summary: "停用全部动画、毛玻璃模糊与状态光效，零动效开销。",
    performance: "极低占用",
  },
  {
    value: "minimal",
    label: "简约",
    summary: "仅保留轻量点击与弹层淡入反馈，停用循环光效与图表动画。",
    performance: "低占用",
  },
  {
    value: "standard",
    label: "标准",
    summary: "页面平滑切换、导航滑块跟随、抽屉弹出与图表绘制，流畅平衡。",
    performance: "推荐默认",
  },
  {
    value: "rich",
    label: "丰富",
    summary: "完整视觉质感：卡片错峰入场、数字缓动、微光骨架、氛围光与主题渐变。",
    performance: "完整体验",
  },
];

export const MOTION_EASE_OUT = [0.22, 1, 0.36, 1] as const;

export const MOTION_SPRING_SNAPPY = {
  type: "spring",
  stiffness: 480,
  damping: 36,
  mass: 0.8,
} as const;

export const MOTION_SPRING_SOFT = {
  type: "spring",
  stiffness: 360,
  damping: 30,
  mass: 0.9,
} as const;

function readSystemReducedMotion(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function useSystemReducedMotion(): boolean {
  const [reduced, setReduced] = useState<boolean>(readSystemReducedMotion);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  return reduced;
}

export function useMotion() {
  const preferred = useUIStore((state) => state.motion);
  const setMotion = useUIStore((state) => state.setMotion);
  const systemReduced = useSystemReducedMotion();

  const effective: MotionLevel = preferred ?? (systemReduced ? "off" : "standard");
  const isSystemDefault = preferred === null;

  return useMemo(
    () => ({
      preferred,
      effective,
      isSystemDefault,
      systemReduced,
      setMotion,
      enabled: effective !== "off",
      isOff: effective === "off",
      isMinimal: effective === "minimal",
      isStandardOrAbove: effective === "standard" || effective === "rich",
      isRich: effective === "rich",
      allowLayout: effective === "standard" || effective === "rich",
      allowPageEnter: effective === "standard" || effective === "rich",
      allowStagger: effective === "rich",
      allowChart: effective === "standard" || effective === "rich",
      allowNumbers: effective === "rich",
      allowLiveRow: effective === "rich",
      allowAmbient: effective === "rich",
      allowThemeTransition: effective === "rich",
      pageDuration: effective === "rich" ? 0.24 : 0.18,
      chartDuration: effective === "rich" ? 620 : 420,
    }),
    [preferred, effective, isSystemDefault, systemReduced, setMotion],
  );
}

/**
 * 仅在 enabled=true（丰富档）时以 requestAnimationFrame 缓动数值。
 * 低档位与页面隐藏时零定时器和零 rAF 开销；高频更新自动节流防抖动。
 */
export function useAnimatedNumber(
  target: number | undefined,
  enabled: boolean,
  options?: { durationMs?: number; minIntervalMs?: number },
): number | undefined {
  const durationMs = options?.durationMs ?? 280;
  const minIntervalMs = options?.minIntervalMs ?? 180;
  const [display, setDisplay] = useState<number | undefined>(target);
  const currentRef = useRef<number | undefined>(target);
  const lastStartRef = useRef<number>(0);

  useEffect(() => {
    if (target === undefined || !Number.isFinite(target)) {
      currentRef.current = target;
      setDisplay(target);
      return;
    }

    const hidden = typeof document !== "undefined" && document.hidden;
    if (!enabled || hidden || currentRef.current === undefined) {
      currentRef.current = target;
      setDisplay(target);
      return;
    }

    const from = currentRef.current;
    if (Math.abs(target - from) < 0.0005) {
      currentRef.current = target;
      setDisplay(target);
      return;
    }

    const now = performance.now();
    if (now - lastStartRef.current < minIntervalMs) {
      currentRef.current = target;
      setDisplay(target);
      return;
    }
    lastStartRef.current = now;

    let rafId = 0;
    const start = now;

    const tick = (frameTime: number) => {
      const elapsed = frameTime - start;
      const progress = Math.min(elapsed / durationMs, 1);
      const eased = 1 - (1 - progress) ** 3;
      const next = from + (target - from) * eased;
      currentRef.current = next;
      setDisplay(next);
      if (progress < 1) {
        rafId = window.requestAnimationFrame(tick);
      } else {
        currentRef.current = target;
        setDisplay(target);
      }
    };

    rafId = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(rafId);
  }, [target, enabled, durationMs, minIntervalMs]);

  if (!enabled) return target;
  return display;
}

/**
 * 实时查询流新行高亮节流：
 * 当每秒涌入大量请求（高 QPS 突发）时自动跳过逐行动画，避免 DOM 与合成层抖动。
 */
export function useThrottledRowFlash(
  topKey: string | undefined,
  enabled: boolean,
  maxEventsPerSecond = 6,
): string | null {
  const [flashKey, setFlashKey] = useState<string | null>(null);
  const prevKeyRef = useRef<string | undefined>(topKey);
  const timestampsRef = useRef<number[]>([]);

  useEffect(() => {
    if (!enabled || !topKey) {
      prevKeyRef.current = topKey;
      setFlashKey(null);
      return;
    }

    if (prevKeyRef.current === undefined) {
      prevKeyRef.current = topKey;
      return;
    }

    if (prevKeyRef.current === topKey) return;
    prevKeyRef.current = topKey;

    if (typeof document !== "undefined" && document.hidden) return;

    const now = performance.now();
    const recent = timestampsRef.current.filter((ts) => now - ts < 1000);
    recent.push(now);
    timestampsRef.current = recent;

    if (recent.length > maxEventsPerSecond) {
      setFlashKey(null);
      return;
    }

    setFlashKey(topKey);
    const timer = window.setTimeout(() => {
      setFlashKey((current) => (current === topKey ? null : current));
    }, 680);

    return () => window.clearTimeout(timer);
  }, [topKey, enabled, maxEventsPerSecond]);

  return enabled ? flashKey : null;
}
