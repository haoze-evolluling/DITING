import { useEffect, useId, useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartSpline, Table2 } from "lucide-react";
import type { TooltipProps } from "recharts";

import { useMotion } from "../../hooks/use-motion";
import { cn } from "../../lib/cn";
import {
  formatCompact,
  formatHour,
  formatNumber,
  hourRangeLabel,
} from "../../lib/format";
import type { HourPoint } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { Skeleton } from "../ui/skeleton";
import { Swap } from "../ui/swap";

const series = [
  { key: "queries", label: "查询", color: "var(--chart-blue)" },
  { key: "blocked", label: "拦截", color: "var(--chart-red)" },
  { key: "cached", label: "缓存命中", color: "var(--chart-violet)" },
] as const;

type SeriesKey = (typeof series)[number]["key"];

function ChartTooltip({ active, payload }: TooltipProps<number, string>) {
  if (!active || !payload || payload.length === 0) return null;
  const point = payload[0]?.payload as { fullLabel?: string } | undefined;
  return (
    <div className="motion-tooltip rounded-xl border border-border bg-surface px-3 py-2 shadow-[var(--shadow-pop)]">
      <div className="mb-1 text-[10.5px] text-text-3">{point?.fullLabel}</div>
      {series.map((item) => {
        const entry = payload.find((candidate) => candidate.dataKey === item.key);
        return (
          <div key={item.key} className="flex items-center gap-2 py-0.5 text-[11.5px]">
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ backgroundColor: item.color }}
            />
            <span className="text-text-3">{item.label}</span>
            <span className="num ml-auto pl-4 font-medium text-text">
              {formatNumber(Number(entry?.value ?? 0))}
            </span>
          </div>
        );
      })}
    </div>
  );
}

export function TrafficChart({
  points,
  loading = false,
  title = "24 小时解析趋势",
  description,
  className,
}: {
  points: HourPoint[];
  loading?: boolean;
  title?: string;
  description?: string;
  className?: string;
}) {
  const [showTable, setShowTable] = useState(false);
  const [animatedOnce, setAnimatedOnce] = useState(false);
  const { allowChart, chartDuration } = useMotion();
  const gradientId = `traffic-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;

  // 仅在首屏数据就绪后播放一次绘制动画；后续轮询刷新不再重播，
  // 避免每 15 秒整张曲线从头重绘造成闪动。
  useEffect(() => {
    if (!allowChart || points.length === 0) return;
    const timer = window.setTimeout(() => setAnimatedOnce(true), 800);
    return () => window.clearTimeout(timer);
  }, [allowChart, points.length]);

  const animateChart = allowChart && !animatedOnce;

  const data = useMemo(
    () =>
      points.map((point) => ({
        ...point,
        label: formatHour(point.hourMs),
        fullLabel: `${formatHour(point.hourMs)} · ${new Date(point.hourMs).toLocaleDateString("zh-CN")}`,
      })),
    [points],
  );

  const latest = data[data.length - 1];
  const totals = useMemo(
    () =>
      data.reduce(
        (accumulator, point) => ({
          queries: accumulator.queries + point.queries,
          blocked: accumulator.blocked + point.blocked,
          cached: accumulator.cached + point.cached,
        }),
        { queries: 0, blocked: 0, cached: 0 },
      ),
    [data],
  );

  const valueFor = (key: SeriesKey): number => {
    if (key === "queries") return latest?.queries ?? 0;
    if (key === "blocked") return latest?.blocked ?? 0;
    return latest?.cached ?? 0;
  };

  return (
    <Card className={cn("flex flex-col overflow-hidden", className)}>
      <CardHeader
        title={title}
        description={description ?? hourRangeLabel(points)}
        actions={
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setShowTable((value) => !value)}
            aria-pressed={showTable}
          >
            {showTable ? <ChartSpline className="h-3.5 w-3.5" /> : <Table2 className="h-3.5 w-3.5" />}
            {showTable ? "图表" : "数据表"}
          </Button>
        }
      />
      <div className="flex flex-wrap gap-x-4 gap-y-1 px-5 pt-3 text-[11px]">
        {series.map((item) => (
          <span key={item.key} className="inline-flex items-center gap-1.5 text-text-3">
            <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: item.color }} />
            {item.label}
            <span className="num font-medium text-text-2">{formatNumber(valueFor(item.key))}</span>
          </span>
        ))}
        <span className="ml-auto text-text-3">
          24h 合计 <span className="num text-text-2">{formatNumber(totals.queries)}</span>
        </span>
      </div>

      <CardContent className="pt-2">
        {loading ? (
          <Skeleton className="h-[228px] w-full" />
        ) : (
          <Swap swapKey={showTable ? "table" : "chart"}>
            {showTable ? (
              <div className="h-[228px] overflow-y-auto rounded-lg border border-border">
                <table className="w-full text-[11.5px]">
                  <caption className="sr-only">最近 24 小时解析趋势数据表</caption>
                  <thead className="sticky top-0 bg-surface-2 text-text-3">
                    <tr>
                      <th className="px-3 py-1.5 text-left font-medium">时间</th>
                      <th className="px-3 py-1.5 text-right font-medium">查询</th>
                      <th className="px-3 py-1.5 text-right font-medium">拦截</th>
                      <th className="px-3 py-1.5 text-right font-medium">缓存</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.map((point) => (
                      <tr key={point.hourMs} className="border-t border-border/70">
                        <td className="mono px-3 py-1 text-text-2">{point.label}</td>
                        <td className="num px-3 py-1 text-right text-text">{formatNumber(point.queries)}</td>
                        <td className="num px-3 py-1 text-right text-text-2">{formatNumber(point.blocked)}</td>
                        <td className="num px-3 py-1 text-right text-text-2">{formatNumber(point.cached)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="h-[228px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={data} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
                    <defs>
                      <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="var(--chart-blue)" stopOpacity={0.26} />
                        <stop offset="100%" stopColor="var(--chart-blue)" stopOpacity={0.02} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid
                      vertical={false}
                      stroke="var(--chart-grid)"
                      strokeDasharray="3 5"
                    />
                    <XAxis
                      dataKey="label"
                      interval={3}
                      tickLine={false}
                      axisLine={false}
                      tick={{ fill: "var(--chart-axis)", fontSize: 10 }}
                      tickMargin={8}
                    />
                    <YAxis
                      width={40}
                      tickLine={false}
                      axisLine={false}
                      allowDecimals={false}
                      tickFormatter={(value: number) => formatCompact(value)}
                      tick={{ fill: "var(--chart-axis)", fontSize: 10 }}
                    />
                    <Tooltip
                      content={<ChartTooltip />}
                      cursor={{ stroke: "var(--chart-axis)", strokeDasharray: "3 4", strokeWidth: 1 }}
                    />
                    <Area
                      type="linear"
                      dataKey="queries"
                      stroke="var(--chart-blue)"
                      strokeWidth={2}
                      fill={`url(#${gradientId})`}
                      isAnimationActive={animateChart}
                      animationDuration={chartDuration}
                      animationEasing="ease-out"
                      activeDot={{ r: 4, strokeWidth: 2, stroke: "var(--surface)" }}
                    />
                    <Line
                      type="linear"
                      dataKey="blocked"
                      stroke="var(--chart-red)"
                      strokeWidth={2}
                      dot={false}
                      isAnimationActive={animateChart}
                      animationDuration={chartDuration}
                      animationEasing="ease-out"
                      activeDot={{ r: 4, strokeWidth: 2, stroke: "var(--surface)" }}
                    />
                    <Line
                      type="linear"
                      dataKey="cached"
                      stroke="var(--chart-violet)"
                      strokeWidth={2}
                      dot={false}
                      isAnimationActive={animateChart}
                      animationDuration={chartDuration}
                      animationEasing="ease-out"
                      activeDot={{ r: 4, strokeWidth: 2, stroke: "var(--surface)" }}
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            )}
          </Swap>
        )}
      </CardContent>
    </Card>
  );
}
