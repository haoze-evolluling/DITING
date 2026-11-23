import { useEffect, useState } from "react";
import { Monitor, Moon, Palette, RotateCw, Sparkles, Sun } from "lucide-react";
import { m } from "motion/react";

import {
  MOTION_EASE_OUT,
  MOTION_LEVEL_OPTIONS,
  MOTION_SPRING_SOFT,
  useAnimatedNumber,
  useMotion,
} from "../../hooks/use-motion";
import { cn } from "../../lib/cn";
import { useUIStore, type Accent, type MotionLevel, type ThemeMode } from "../../stores/ui";
import { Card, CardContent, CardHeader } from "../ui/card";
import { Segmented } from "../ui/segmented";

const themeOptions: { value: ThemeMode; label: string; icon: typeof Sun }[] = [
  { value: "system", label: "跟随系统", icon: Monitor },
  { value: "light", label: "浅色", icon: Sun },
  { value: "dark", label: "深色", icon: Moon },
];

const accentOptions: { value: Accent; label: string; color: string }[] = [
  { value: "blue", label: "信号蓝", color: "#2F7BF6" },
  { value: "jade", label: "青玉", color: "#0E9B70" },
  { value: "violet", label: "星紫", color: "#7C5CF0" },
  { value: "amber", label: "琥珀", color: "#C07808" },
];

const motionOptions: { value: MotionLevel; label: string }[] = MOTION_LEVEL_OPTIONS.map(
  (item) => ({ value: item.value, label: item.label }),
);

function MotionPreviewStage({ level }: { level: MotionLevel }) {
  const [phase, setPhase] = useState(0);

  useEffect(() => {
    let innerFrame = 0;
    const outerFrame = window.requestAnimationFrame(() => {
      innerFrame = window.requestAnimationFrame(() => {
        setPhase(1);
      });
    });
    return () => {
      window.cancelAnimationFrame(outerFrame);
      window.cancelAnimationFrame(innerFrame);
    };
  }, []);

  const isRich = level === "rich";
  const isStandardOrAbove = level === "standard" || level === "rich";
  const targetQps = phase === 1 ? 42.8 : 16.2;
  const animatedQps = useAnimatedNumber(targetQps, isRich, {
    durationMs: 420,
    minIntervalMs: 0,
  });

  const barA = phase === 1 ? 82 : 34;
  const barB = phase === 1 ? 56 : 22;

  const stageBody = (
    <>
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="live-dot h-2 w-2 rounded-full bg-good text-good" />
          <span className="text-[11px] font-medium text-text">实时状态</span>
          <span className="inline-block h-2 w-10 rounded-full bg-surface-3" />
        </div>
        <span className="num text-[11.5px] font-semibold text-accent">
          {(animatedQps ?? targetQps).toFixed(1)} QPS
        </span>
      </div>
      <div className="mt-2 space-y-1.5">
        <div className="h-1.5 overflow-hidden rounded-full bg-surface-3">
          <div
            className="motion-bar h-full rounded-full bg-accent"
            style={{ width: `${barA}%` }}
          />
        </div>
        <div className="h-1.5 overflow-hidden rounded-full bg-surface-3">
          <div
            className="motion-bar h-full rounded-full bg-violet/80"
            style={{ width: `${barB}%` }}
          />
        </div>
      </div>
    </>
  );

  if (isStandardOrAbove) {
    return (
      <m.div
        initial={{ opacity: 0, y: isRich ? 7 : 4, scale: isRich ? 0.98 : 1 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={
          isRich
            ? MOTION_SPRING_SOFT
            : { duration: 0.19, ease: MOTION_EASE_OUT }
        }
        className="relative rounded-lg border border-border bg-surface px-2.5 py-2 shadow-xs"
      >
        {stageBody}
      </m.div>
    );
  }

  return (
    <div
      className={cn(
        "relative rounded-lg border border-border bg-surface px-2.5 py-2 shadow-xs",
        level === "minimal" && "animate-[motion-fade-in_120ms_ease-out]",
      )}
    >
      {stageBody}
    </div>
  );
}

export function AppearanceCard() {
  const theme = useUIStore((state) => state.theme);
  const accent = useUIStore((state) => state.accent);
  const setTheme = useUIStore((state) => state.setTheme);
  const setAccent = useUIStore((state) => state.setAccent);
  const { effective: motion, isSystemDefault, systemReduced, setMotion } = useMotion();
  const [replayKey, setReplayKey] = useState(0);

  const currentMotionMeta =
    MOTION_LEVEL_OPTIONS.find((item) => item.value === motion) ?? MOTION_LEVEL_OPTIONS[2];

  const handleMotionChange = (next: MotionLevel) => {
    setMotion(next);
    setReplayKey((count) => count + 1);
  };

  return (
    <Card>
      <CardHeader title="外观" description="主题、强调色与动画档位立即生效，并保存在当前浏览器。" />
      <CardContent className="space-y-4 pt-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="flex items-center gap-2 text-[12px] text-text-2">
            <Monitor className="h-3.5 w-3.5 text-text-3" />
            主题
          </span>
          <Segmented value={theme} options={themeOptions} onChange={setTheme} />
        </div>

        <div>
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-[12px] text-text-2">
              <Palette className="h-3.5 w-3.5 text-text-3" />
              强调色
            </span>
            <span className="text-[11px] text-text-3">
              {accentOptions.find((option) => option.value === accent)?.label}
            </span>
          </div>
          <div className="mt-2.5 flex flex-wrap gap-2">
            {accentOptions.map((option) => (
              <button
                key={option.value}
                type="button"
                aria-pressed={accent === option.value}
                onClick={() => setAccent(option.value)}
                className={cn(
                  "motion-btn flex items-center gap-2 rounded-lg border px-2.5 py-1.5 text-[11.5px]",
                  accent === option.value
                    ? "border-accent bg-accent-soft text-text"
                    : "border-border text-text-2 hover:bg-surface-2",
                )}
              >
                <span
                  className="h-3 w-3 rounded-full ring-1 ring-black/10"
                  style={{ backgroundColor: option.color }}
                />
                {option.label}
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-2.5 border-t border-border/60 pt-3.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="flex items-center gap-2 text-[12px] text-text-2">
              <Sparkles className="h-3.5 w-3.5 text-text-3" />
              动画效果
            </span>
            <Segmented value={motion} options={motionOptions} onChange={handleMotionChange} />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] leading-4 text-text-3">
            <span>{currentMotionMeta.summary}</span>
            <span className="shrink-0 rounded-md bg-surface-3 px-1.5 py-0.5 text-[10px] text-text-2">
              {isSystemDefault && systemReduced
                ? "跟随系统 · 已减弱"
                : currentMotionMeta.performance}
            </span>
          </div>

          <div className="relative overflow-hidden rounded-xl border border-border bg-surface-2 px-3 py-2.5">
            <div
              aria-hidden
              className="motion-glow motion-glow-ambient pointer-events-none absolute -right-6 -top-8 h-20 w-20 rounded-full bg-accent/20 blur-xl"
            />
            <div className="relative flex items-center justify-between gap-2 pb-2">
              <span className="text-[10.5px] text-text-3">即时动效体验</span>
              <button
                type="button"
                onClick={() => setReplayKey((count) => count + 1)}
                className="motion-btn inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10.5px] text-text-3 hover:bg-surface-3 hover:text-text"
              >
                <RotateCw className="h-2.5 w-2.5" />
                重播
              </button>
            </div>
            <MotionPreviewStage key={`${motion}-${replayKey}`} level={motion} />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
