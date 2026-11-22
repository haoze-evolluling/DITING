import { useEffect, useState } from "react";
import { Activity, Play, Square } from "lucide-react";

import { formatNumber, formatUptime } from "../../lib/format";
import { resolverModeLabel } from "../../lib/labels";
import type { MetricsStatus, StatusResponse } from "../../lib/types";
import { cn } from "../../lib/cn";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card } from "../ui/card";
import { Skeleton } from "../ui/skeleton";

function QpsSparkline({ qps }: { qps: number }) {
  const [history, setHistory] = useState<number[]>([]);

  useEffect(() => {
    setHistory((previous) => [...previous, qps].slice(-32));
  }, [qps]);

  const width = 560;
  const height = 40;
  const peak = Math.max(...history, 0);
  const scale = Math.max(peak, 1);
  const step = history.length > 1 ? width / (history.length - 1) : width;
  const points = history
    .map(
      (value, index) =>
        `${(index * step).toFixed(2)},${(height - (value / scale) * (height - 5) - 2).toFixed(2)}`,
    )
    .join(" ");
  const lastX = Math.max((history.length - 1) * step, 0);
  const peakLabel = peak < 10 ? peak.toFixed(2) : peak.toFixed(1);
  const hasActivity = history.length > 1 && peak > 0;

  return (
    <div className="min-w-0 flex-1">
      <div className="flex items-center justify-between text-[10px] text-text-3">
        <span>最近活动</span>
        <span className="num">峰值 {peakLabel} QPS</span>
      </div>
      {hasActivity ? (
        <svg
          viewBox={`0 0 ${width} ${height}`}
          preserveAspectRatio="none"
          className="mt-1 h-9 w-full text-accent"
          role="img"
          aria-label={`最近 QPS 走势，当前 ${qps.toFixed(1)}，峰值 ${peakLabel}`}
        >
          <line
            x1="0"
            y1={height - 1}
            x2={width}
            y2={height - 1}
            stroke="currentColor"
            strokeOpacity="0.16"
            strokeWidth="1"
            vectorEffect="non-scaling-stroke"
          />
          <polygon
            points={`0,${height} ${points} ${lastX.toFixed(2)},${height}`}
            fill="currentColor"
            fillOpacity="0.08"
          />
          <polyline
            points={points}
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
          />
        </svg>
      ) : (
        <div className="mt-1 flex h-9 items-center justify-center rounded-md border border-dashed border-border/80 text-[10px] text-text-3">
          暂无查询活动
        </div>
      )}
    </div>
  );
}

export function HeroStatus({
  status,
  metrics,
  loading,
  busy,
  onToggleDns,
  onOpenDiagnostics,
}: {
  status?: StatusResponse;
  metrics?: MetricsStatus | null;
  loading: boolean;
  busy: boolean;
  onToggleDns: () => void;
  onOpenDiagnostics: () => void;
}) {
  const running = status?.dns.running ?? false;
  const qps = metrics?.qps ?? status?.metrics.qps ?? 0;
  const uptime = status?.uptimeSeconds ?? 0;
  const addresses = status?.dns.listenAddresses ?? [];
  const upstreams = status?.dns.upstreams ?? [];
  const activeUpstreams = upstreams.filter((upstream) => upstream.active).length;
  const takeover = status?.takeover;

  return (
    <Card className="card-sheen relative flex min-h-[248px] flex-col overflow-hidden">
      <div
        aria-hidden
        className="pointer-events-none absolute -right-20 -top-24 h-64 w-64 rounded-full bg-accent/15 blur-3xl"
      />
      <div className="relative flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-5 pt-4">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <span className="text-[12px] font-medium text-text-3">DNS 核心</span>
          <Badge tone="neutral">{resolverModeLabel(status?.dns.mode)}</Badge>
          {takeover?.active ? <Badge tone="accent">系统 DNS 已接管</Badge> : null}
        </div>
        <div className="ml-auto flex flex-wrap items-center gap-2">
          <Button size="sm" variant="ghost" onClick={onOpenDiagnostics}>
            <Activity className="h-3.5 w-3.5" />
            网络诊断
          </Button>
          <Button
            size="sm"
            variant={running ? "dangerSoft" : "primary"}
            onClick={onToggleDns}
            loading={busy}
            disabled={!status && !loading}
          >
            {running ? <Square className="h-3 w-3" /> : <Play className="h-3 w-3" />}
            {running ? "停止解析" : "启动解析"}
          </Button>
        </div>
      </div>

      <div className="relative flex flex-1 flex-col justify-between gap-4 px-5 pb-4 pt-3">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            {loading ? (
              <Skeleton className="h-10 w-40" />
            ) : (
              <div className="flex items-center gap-2.5">
                <span
                  className={cn(
                    "live-dot h-2.5 w-2.5 rounded-full",
                    !status
                      ? "bg-text-3 text-text-3"
                      : running
                        ? "bg-good text-good"
                        : "bg-text-3 text-text-3",
                  )}
                />
                <span className="text-[32px] font-semibold leading-none tracking-[-0.045em] text-text">
                  {!status ? "状态未知" : running ? "运行中" : "已停止"}
                </span>
              </div>
            )}
            <p className="mt-2 text-[12px] text-text-3">
              {!status
                ? "无法读取运行状态，请检查本机管理服务连接。"
                : running
                  ? `已稳定运行 ${formatUptime(uptime)}，正在为${takeover?.active ? "本机与局域网" : "本机"}提供解析`
                  : "解析服务当前未运行，点击右上角按钮启动"}
            </p>
            <div className="mt-3 flex flex-wrap gap-1.5">
              {addresses.length > 0 ? (
                addresses.slice(0, 3).map((address) => (
                  <span
                    key={address}
                    className="mono rounded-md border border-border bg-surface-2 px-1.5 py-0.5 text-[10.5px] text-text-2"
                  >
                    {address}
                  </span>
                ))
              ) : (
                <span className="text-[11px] text-text-3">未监听任何地址</span>
              )}
            </div>
          </div>

          <div className="shrink-0 text-right">
            <div className="num text-[28px] font-semibold leading-none tracking-[-0.035em] text-text">
              {qps.toFixed(1)}
            </div>
            <div className="mt-1 text-[10.5px] text-text-3">当前 QPS</div>
          </div>
        </div>

        <QpsSparkline qps={qps} />
      </div>

      <div className="relative grid grid-cols-2 divide-x divide-border border-t border-border bg-surface-2/65 sm:grid-cols-4">
        {[
          { label: "版本", value: status?.version ? `v${status.version}` : "—" },
          { label: "运行时长", value: formatUptime(uptime) },
          { label: "活跃上游", value: `${activeUpstreams}/${upstreams.length}` },
          { label: "累计查询", value: formatNumber(status?.metrics.totalQueries) },
        ].map((item) => (
          <div key={item.label} className="min-w-0 px-4 py-2.5">
            <div className="truncate text-[10.5px] text-text-3">{item.label}</div>
            <div className="num mt-0.5 truncate text-[12.5px] font-medium text-text">
              {item.value}
            </div>
          </div>
        ))}
      </div>
    </Card>
  );
}
