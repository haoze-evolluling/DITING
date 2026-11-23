import { useState } from "react";
import { ArrowRight, Radio } from "lucide-react";
import { NavLink } from "react-router-dom";

import { useMotion, useThrottledRowFlash } from "../../hooks/use-motion";
import { displayDomain, formatClock, formatLatency } from "../../lib/format";
import type { QueryRecord } from "../../lib/types";
import { cn } from "../../lib/cn";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { StatusBadge } from "../ui/status-badge";
import { QueryDetailSheet } from "../logs/query-detail-sheet";

export function RecentQueries({
  queries,
  connected,
  live,
}: {
  queries: QueryRecord[];
  connected: boolean;
  live: boolean;
}) {
  const [selected, setSelected] = useState<QueryRecord | null>(null);
  const { allowLiveRow } = useMotion();
  const rows = queries.slice(0, 7);
  const topKey = rows[0] ? `${rows[0].ts}-${rows[0].domain}` : undefined;
  const flashKey = useThrottledRowFlash(topKey, live && allowLiveRow);

  return (
    <>
      <Card>
        <CardHeader
          title={live ? "实时查询" : "最近查询"}
          description={
            live ? "来自本机与局域网的最近解析请求" : "最近保存的查询记录"
          }
          actions={
            <div className="flex items-center gap-2">
              <Badge tone={live ? (connected ? "good" : "warn") : "neutral"} dot>
                {live ? (connected ? "实时" : "重连中") : "历史"}
              </Badge>
              <Button size="sm" variant="ghost" asChild>
                <NavLink to="/logs">
                  查看全部
                  <ArrowRight className="h-3.5 w-3.5" />
                </NavLink>
              </Button>
            </div>
          }
        />
        <CardContent className="pt-1">
          {rows.length === 0 ? (
            <EmptyState
              icon={Radio}
              title="等待查询"
              description="DNS 服务运行时，最新解析会实时出现在这里。"
            />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px]">
                <caption className="sr-only">最近解析请求</caption>
                <thead>
                  <tr className="text-left text-[10.5px] text-text-3">
                    <th className="w-[72px] pb-1.5 font-medium">时间</th>
                    <th className="pb-1.5 font-medium">域名</th>
                    <th className="w-[130px] pb-1.5 font-medium">客户端</th>
                    <th className="w-[84px] pb-1.5 font-medium">状态</th>
                    <th className="w-[72px] pb-1.5 text-right font-medium">耗时</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((record, index) => {
                    const rowId = `${record.ts}-${record.domain}`;
                    return (
                      <tr
                        key={`${rowId}-${index}`}
                        tabIndex={0}
                        onClick={() => setSelected(record)}
                        onKeyDown={(event) => {
                          if (event.key === "Enter") setSelected(record);
                        }}
                        className={cn(
                          "cursor-pointer border-t border-border/60 text-[11.5px] transition-colors hover:bg-surface-2 focus-visible:bg-surface-2 focus-visible:outline-none",
                          index === 0 && flashKey === rowId && "motion-row-flash",
                        )}
                      >
                      <td className="num whitespace-nowrap py-1.5 pr-2 text-text-3">
                        {formatClock(record.ts)}
                      </td>
                      <td className="max-w-0 py-1.5 pr-3">
                        <span className="mono block truncate text-text">
                          {displayDomain(record.domain)}
                        </span>
                      </td>
                      <td className="truncate py-1.5 pr-2 text-text-3">
                        {record.clientName || record.clientIP || "—"}
                      </td>
                      <td className="whitespace-nowrap py-1.5">
                        <StatusBadge status={record.status} />
                      </td>
                      <td className="num whitespace-nowrap py-1.5 text-right text-text-2">
                        {formatLatency(record.durationMs)}
                      </td>
                    </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      <QueryDetailSheet
        record={selected}
        open={selected !== null}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      />
    </>
  );
}
