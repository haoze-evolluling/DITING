import { formatLatency, formatNumber, formatRatio } from "../../lib/format";
import type { QueryLogStats } from "../../lib/types";
import { Card, CardContent, CardHeader } from "../ui/card";
import { LoadingState } from "../ui/loading";

function Item({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint: string;
}) {
  return (
    <div className="min-w-0">
      <div className="truncate text-[11px] text-text-3">{label}</div>
      <div className="num mt-1 truncate text-[20px] font-semibold leading-6 tracking-[-0.03em] text-text">
        {value}
      </div>
      <div className="mt-0.5 truncate text-[10.5px] text-text-3">{hint}</div>
    </div>
  );
}

export function LogSummary({
  stats,
  loading,
}: {
  stats?: QueryLogStats;
  loading: boolean;
}) {
  const summary = stats?.summary;
  return (
    <Card className="flex flex-col">
      <CardHeader title="解析概览" description="最近 24 小时" />
      <CardContent className="grid flex-1 grid-cols-2 content-center gap-x-4 gap-y-6 pt-3">
        {loading ? (
          <LoadingState label="正在加载解析概览…" className="col-span-2 min-h-[120px]" />
        ) : (
          <>
            <Item
              label="查询总量"
              value={formatNumber(summary?.queries)}
              hint={`${formatNumber(summary?.forwarded)} 次转发`}
            />
            <Item
              label="拦截数量"
              value={formatNumber(summary?.blocked)}
              hint={`${formatNumber(summary?.errors)} 次失败`}
            />
            <Item
              label="缓存命中率"
              value={formatRatio(summary?.cacheHitRate)}
              hint={`${formatNumber(summary?.cached)} 次命中`}
            />
            <Item
              label="平均延迟"
              value={formatLatency(summary?.avgResponseMs)}
              hint="含缓存与转发请求"
            />
          </>
        )}
      </CardContent>
    </Card>
  );
}
