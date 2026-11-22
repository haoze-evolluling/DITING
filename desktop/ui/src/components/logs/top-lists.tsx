import { useState } from "react";
import { ListOrdered } from "lucide-react";

import { displayDomain, formatNumber } from "../../lib/format";
import type { NameCount, QueryLogStats } from "../../lib/types";
import { cn } from "../../lib/cn";
import { Card, CardContent, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { Segmented } from "../ui/segmented";

type Tab = "domains" | "blocked" | "clients";

const tabs: { value: Tab; label: string }[] = [
  { value: "domains", label: "域名" },
  { value: "blocked", label: "拦截" },
  { value: "clients", label: "客户端" },
];

const toneClass: Record<Tab, string> = {
  domains: "bg-accent/12",
  blocked: "bg-danger/12",
  clients: "bg-violet/12",
};

function Rows({ items, tone }: { items: NameCount[]; tone: Tab }) {
  if (items.length === 0) {
    return <EmptyState icon={ListOrdered} title="暂无数据" description="统计窗口内还没有记录。" />;
  }
  const max = Math.max(...items.map((item) => item.count), 1);
  return (
    <div className="space-y-0.5">
      {items.slice(0, 10).map((item, index) => (
        <div
          key={`${item.name}-${index}`}
          className="relative flex items-center gap-2 overflow-hidden rounded-md px-2 py-1.5"
        >
          <span
            aria-hidden
            className={cn("absolute inset-y-0 left-0 rounded-md", toneClass[tone])}
            style={{ width: `${Math.max((item.count / max) * 100, 3)}%` }}
          />
          <span className="num relative w-4 shrink-0 text-[10px] text-text-3">{index + 1}</span>
          <span className="mono relative min-w-0 flex-1 truncate text-[11.5px] text-text" title={item.name}>
            {displayDomain(item.name)}
          </span>
          <span className="num relative text-[11px] text-text-2">{formatNumber(item.count)}</span>
        </div>
      ))}
    </div>
  );
}

export function TopLists({ stats, loading }: { stats?: QueryLogStats; loading: boolean }) {
  const [tab, setTab] = useState<Tab>("domains");
  const items =
    tab === "domains"
      ? stats?.topDomains ?? []
      : tab === "blocked"
        ? stats?.topBlocked ?? []
        : stats?.topClients ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="排名"
        description="统计窗口内 Top 10"
        className="flex-wrap"
        actions={
          <Segmented value={tab} options={tabs} onChange={setTab} />
        }
      />
      <CardContent className="flex-1 pt-1">
        {loading ? (
          <div className="space-y-1.5">
            {Array.from({ length: 7 }).map((_, index) => (
              <div key={index} className="h-7 animate-pulse rounded-md bg-surface-3" />
            ))}
          </div>
        ) : (
          <Rows items={items} tone={tab} />
        )}
      </CardContent>
    </Card>
  );
}
