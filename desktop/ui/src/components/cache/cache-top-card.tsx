import { useState } from "react";
import { Flame } from "lucide-react";

import { useCacheTop } from "../../hooks/use-api";
import { formatNumber, formatRelative } from "../../lib/format";
import { LoadingState } from "../ui/loading";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { Select } from "../ui/select";

const topOptions = [
  { value: "10", label: "前 10" },
  { value: "20", label: "前 20" },
  { value: "50", label: "前 50" },
];

export function CacheTopCard() {
  const [limit, setLimit] = useState(10);
  const top = useCacheTop(limit);
  const items = top.data ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="高频命中"
        description="按缓存命中次数排序的热点域名。"
        actions={
          <Select
            className="w-[96px]"
            value={String(limit)}
            options={topOptions}
            onValueChange={(value) => setLimit(Number(value))}
            ariaLabel="排行数量"
          />
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {top.isLoading ? (
          <LoadingState label="正在加载命中排行…" className="min-h-[160px]" />
        ) : items.length === 0 ? (
          <EmptyState
            icon={Flame}
            title="暂无命中统计"
            description="缓存命中后会在这里生成域名排行。"
          />
        ) : (
          <div className="divide-y divide-border/70">
            {items.map((item, index) => (
              <div key={`${item.domain}-${item.qtype}`} className="flex items-center gap-3 py-2.5">
                <span className="w-5 shrink-0 text-center text-[11px] font-semibold text-text-3">
                  {index + 1}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="mono truncate text-[11.5px] text-text" title={item.domain}>
                    {item.domain}
                  </div>
                  <div className="mt-0.5 text-[10px] text-text-3">
                    {item.lastHitAt ? `最近 ${formatRelative(item.lastHitAt)}` : "—"}
                  </div>
                </div>
                <Badge tone="neutral">{item.qtype}</Badge>
                <span className="num w-16 shrink-0 text-right text-[11.5px] text-text-2">
                  {formatNumber(item.hitCount)}
                </span>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
