import { SearchX } from "lucide-react";

import { useMotion, useThrottledRowFlash } from "../../hooks/use-motion";
import { cn } from "../../lib/cn";
import { displayDomain, formatDateTime, formatLatency } from "../../lib/format";
import { cacheHitLabel } from "../../lib/labels";
import type { QueryRecord } from "../../lib/types";
import { LoadingState } from "../ui/loading";
import { EmptyState } from "../ui/empty";
import { StatusBadge } from "../ui/status-badge";

export function QueryTable({
  rows,
  loading,
  live,
  onSelect,
}: {
  rows: QueryRecord[];
  loading: boolean;
  live: boolean;
  onSelect: (record: QueryRecord) => void;
}) {
  const { allowLiveRow } = useMotion();
  const topKey = rows[0] ? `${rows[0].ts}-${rows[0].domain}` : undefined;
  const flashKey = useThrottledRowFlash(topKey, live && allowLiveRow);

  if (loading) {
    return <LoadingState label="正在加载查询记录…" className="min-h-[420px]" />;
  }

  if (rows.length === 0) {
    return (
      <EmptyState
        icon={SearchX}
        title={live ? "等待查询" : "没有匹配的查询记录"}
        description={
          live
            ? "实时查询流已开启，DNS 服务收到请求后会立即显示。"
            : "尝试放宽域名、客户端或状态筛选条件。"
        }
      />
    );
  }

  return (
    <div className="max-h-[560px] overflow-auto">
      <table className="w-full min-w-[720px] border-collapse">
        <caption className="sr-only">查询日志</caption>
        <thead className="motion-glass sticky top-0 z-10 bg-surface/95 backdrop-blur">
          <tr className="text-left text-[10.5px] text-text-3">
            <th className="w-[122px] px-3 py-2 font-medium">时间</th>
            <th className="px-3 py-2 font-medium">域名</th>
            <th className="hidden w-[76px] px-3 py-2 font-medium sm:table-cell">类型</th>
            <th className="hidden w-[150px] px-3 py-2 font-medium md:table-cell">客户端</th>
            <th className="hidden w-[110px] px-3 py-2 font-medium lg:table-cell">上游</th>
            <th className="w-[92px] px-3 py-2 font-medium">状态</th>
            <th className="w-[76px] px-3 py-2 text-right font-medium">耗时</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((record, index) => {
            const rowId = `${record.ts}-${record.domain}`;
            return (
              <tr
                key={`${rowId}-${index}`}
                tabIndex={0}
                onClick={() => onSelect(record)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") onSelect(record);
                }}
                className={cn(
                  "cursor-pointer border-t border-border/60 text-[11.5px] transition-colors hover:bg-surface-2 focus-visible:bg-surface-2 focus-visible:outline-none",
                  index === 0 && flashKey === rowId && "motion-row-flash",
                )}
              >
                <td className="num whitespace-nowrap px-3 py-1.5 text-text-3">
                  {formatDateTime(record.ts)}
                </td>
                <td className="max-w-0 px-3 py-1.5">
                  <span
                    className="mono block truncate text-text"
                    title={displayDomain(record.domain)}
                  >
                    {displayDomain(record.domain)}
                  </span>
                </td>
                <td className="hidden px-3 py-1.5 sm:table-cell">
                  <span className="rounded bg-surface-3 px-1.5 py-0.5 text-[10px] font-medium text-text-2">
                    {record.qtype || "—"}
                  </span>
                </td>
                <td className="hidden max-w-0 truncate px-3 py-1.5 text-text-3 md:table-cell">
                  {record.clientName || record.clientIP || "—"}
                </td>
                <td className="hidden max-w-0 truncate px-3 py-1.5 text-text-3 lg:table-cell">
                  {record.upstreamProvider ||
                    (record.cacheHit ? cacheHitLabel(record.cacheHit) : "—")}
                </td>
                <td className="px-3 py-1.5">
                  <StatusBadge status={record.status} />
                </td>
                <td className="num whitespace-nowrap px-3 py-1.5 text-right text-text-2">
                  {formatLatency(record.durationMs)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
