import { Activity, Database, ShieldBan, Timer } from "lucide-react";

import { useAnimatedNumber, useMotion } from "../../hooks/use-motion";
import {
  formatLatency,
  formatNumber,
  formatPercent,
  formatRatio,
} from "../../lib/format";
import type { MetricsStatus, StatusResponse } from "../../lib/types";
import { StatTile } from "../ui/stat-tile";

export function StatGrid({
  status,
  metrics,
  loading,
}: {
  status?: StatusResponse;
  metrics?: MetricsStatus | null;
  loading: boolean;
}) {
  const { allowNumbers } = useMotion();
  const effective = metrics ?? status?.metrics;
  const filter = status?.filter;
  const cache = status?.cache;

  const totalQueries = useAnimatedNumber(effective?.totalQueries, allowNumbers);
  const blockRate = useAnimatedNumber(filter?.blockRate, allowNumbers);
  const hitRatio = useAnimatedNumber(cache?.hitRatio, allowNumbers);
  const avgLatency = useAnimatedNumber(effective?.avgLatencyMs, allowNumbers);

  return (
    <div className="card-grid-4">
      <StatTile
        label="查询总量"
        value={formatNumber(totalQueries !== undefined ? Math.round(totalQueries) : undefined)}
        hint={`当前 ${(effective?.qps ?? 0).toFixed(1)} QPS`}
        icon={Activity}
        tone="accent"
        loading={loading}
      />
      <StatTile
        label="拦截比例"
        value={formatPercent(blockRate)}
        hint={`${formatNumber(filter?.blockedQueries)} 次拦截 · ${formatNumber(filter?.totalRules)} 条规则`}
        icon={ShieldBan}
        tone="danger"
        loading={loading}
      />
      <StatTile
        label="缓存命中率"
        value={formatRatio(hitRatio)}
        hint={`${formatNumber(cache?.entryCount)} / ${formatNumber(cache?.maxEntries)} 条目`}
        icon={Database}
        tone="violet"
        loading={loading}
      />
      <StatTile
        label="平均解析延迟"
        value={formatLatency(avgLatency)}
        hint={`${formatNumber(effective?.failedQueries)} 次失败 · ${formatNumber(status?.dns.upstreams.length)} 个上游`}
        icon={Timer}
        tone="good"
        loading={loading}
      />
    </div>
  );
}
