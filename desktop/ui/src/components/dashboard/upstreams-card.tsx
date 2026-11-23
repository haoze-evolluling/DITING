import { Globe2 } from "lucide-react";

import { formatLatency, formatNumber } from "../../lib/format";
import { protocolLabel, resolverModeLabel } from "../../lib/labels";
import type { QueryLogStats, StatusResponse } from "../../lib/types";
import { cn } from "../../lib/cn";
import { LoadingState } from "../ui/loading";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";

export function UpstreamsCard({
  status,
  stats,
  loading,
}: {
  status?: StatusResponse;
  stats?: QueryLogStats;
  loading: boolean;
}) {
  const upstreams = status?.dns.upstreams ?? [];
  const bootstrap = status?.dns.bootstrap;
  const active = upstreams.filter((upstream) => upstream.active).length;
  const summary = stats?.summary;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="上游解析"
        description={`解析策略：${resolverModeLabel(status?.dns.mode)}`}
        actions={
          <Badge tone={active > 0 ? "good" : "warn"} dot>
            {active}/{upstreams.length} 活跃
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {loading ? (
          <LoadingState label="正在加载上游状态…" className="min-h-[160px]" />
        ) : upstreams.length === 0 ? (
          <EmptyState
            icon={Globe2}
            title="尚未配置上游"
            description="下一阶段将在此提供上游服务商管理。"
          />
        ) : (
          <div className="divide-y divide-border/70">
            {upstreams.map((upstream) => (
              <div key={upstream.id} className="flex items-center gap-3 py-2.5">
                <span
                  className={cn(
                    "h-1.5 w-1.5 shrink-0 rounded-full",
                    upstream.active ? "bg-good" : "bg-text-3",
                  )}
                  title={upstream.active ? "活跃" : "未启用"}
                />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="truncate text-[12.5px] font-medium text-text">
                      {upstream.id}
                    </span>
                    <Badge tone="neutral">{protocolLabel(upstream.protocol)}</Badge>
                  </div>
                  <div className="mono mt-0.5 truncate text-[10.5px] text-text-3">
                    {upstream.server}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="num text-[12.5px] font-medium text-text">
                    {formatLatency(upstream.avgLatencyMs)}
                  </div>
                  <div className="num mt-0.5 text-[10px] text-text-3">
                    {formatNumber(upstream.successCount)} 成功
                    {upstream.failureCount > 0 ? (
                      <span className="text-danger"> · {formatNumber(upstream.failureCount)} 失败</span>
                    ) : null}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="mt-auto pt-3">
          <div className="rounded-xl border border-border bg-surface-2 px-3.5 py-3">
            <div className="flex items-center justify-between text-[10.5px] text-text-3">
              <span>最近 24 小时解析路径</span>
              <span className="num">共 {formatNumber(summary?.queries)} 次</span>
            </div>
            <div className="mt-2 grid grid-cols-3 divide-x divide-border">
              {[
                { label: "转发", value: summary?.forwarded, color: "text-text" },
                { label: "缓存命中", value: summary?.cached, color: "text-violet" },
                { label: "规则拦截", value: summary?.blocked, color: "text-danger" },
              ].map((item, index) => (
                <div key={item.label} className={index === 0 ? "min-w-0 pr-2" : "min-w-0 px-2"}>
                  <div className="num truncate text-[17px] font-semibold leading-6 tracking-[-0.02em] text-text">
                    {formatNumber(item.value)}
                  </div>
                  <div className={`mt-0.5 truncate text-[10px] ${item.color}`}>{item.label}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </CardContent>
      {bootstrap?.enabled && bootstrap.servers.length > 0 ? (
        <CardFooter className="bg-surface-2/60">
          <span className="text-[10.5px] text-text-3">Bootstrap</span>
          <div className="flex flex-wrap justify-end gap-1.5">
            {bootstrap.servers.slice(0, 3).map((server) => (
              <span
                key={server.id}
                className="mono rounded-md border border-border bg-surface px-1.5 py-0.5 text-[10px] text-text-2"
                title={`${server.name} · ${server.address}`}
              >
                {server.name}
              </span>
            ))}
          </div>
        </CardFooter>
      ) : null}
    </Card>
  );
}
