import { useState } from "react";
import { Database, Search } from "lucide-react";

import { useCacheEntries } from "../../hooks/use-api";
import { formatNumber, formatRelative } from "../../lib/format";
import type { CacheEntry } from "../../lib/types";
import { LoadingState } from "../ui/loading";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { Input } from "../ui/input";
import { Select } from "../ui/select";

const limitOptions = [
  { value: "50", label: "50 条" },
  { value: "100", label: "100 条" },
  { value: "200", label: "200 条" },
  { value: "500", label: "500 条" },
];

function statusTone(entry: CacheEntry): { tone: "good" | "violet" | "warn"; label: string } {
  if (entry.isNegative) return { tone: "warn", label: "否定" };
  if (entry.status === "stale") return { tone: "violet", label: "过期" };
  return { tone: "good", label: "有效" };
}

export function CacheEntriesCard() {
  const [input, setInput] = useState("");
  const [query, setQuery] = useState("");
  const [limit, setLimit] = useState(100);
  const entries = useCacheEntries(query, limit);
  const data = entries.data;

  const submit = () => setQuery(input.trim());

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="缓存条目"
        description="按域名检索当前内存缓存，展示剩余 TTL 与命中次数。"
        actions={
          <Badge tone="neutral">
            {formatNumber(data?.total ?? 0)} 条
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        <div className="flex flex-col gap-2 sm:flex-row">
          <Input
            className="sm:flex-1"
            leading={<Search className="h-3.5 w-3.5" />}
            value={input}
            placeholder="搜索域名"
            onChange={(event) => setInput(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") submit();
            }}
          />
          <Select
            className="shrink-0 sm:w-[110px]"
            value={String(limit)}
            options={limitOptions}
            onValueChange={(value) => setLimit(Number(value))}
            ariaLabel="条目数量"
          />
          <Button
            className="shrink-0"
            variant="secondary"
            onClick={submit}
            loading={entries.isFetching}
          >
            搜索
          </Button>
        </div>

        <div className="mt-3 min-h-0 flex-1">
          {entries.isLoading ? (
            <LoadingState label="正在加载缓存条目…" className="min-h-[220px]" />
          ) : !data || data.entries.length === 0 ? (
            <EmptyState
              icon={Database}
              title={query ? "没有匹配的缓存条目" : "缓存为空"}
              description={
                query
                  ? "尝试更换关键字，或清空搜索查看全部条目。"
                  : "DNS 查询命中后，应答会按缓存策略写入这里。"
              }
            />
          ) : (
            <div className="max-h-[420px] overflow-auto pr-1">
              <table className="w-full min-w-[340px] border-collapse text-left">
                <thead>
                  <tr className="text-[10.5px] text-text-3">
                    <th className="pb-1.5 font-medium">域名</th>
                    <th className="pb-1.5 text-center font-medium">类型</th>
                    <th className="pb-1.5 text-right font-medium">剩余 TTL</th>
                    <th className="pb-1.5 text-right font-medium">命中</th>
                    <th className="pb-1.5 text-right font-medium">状态</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/60">
                  {data.entries.map((entry) => {
                    const status = statusTone(entry);
                    return (
                      <tr key={`${entry.domain}-${entry.qtype}`} className="align-middle">
                        <td className="max-w-0 py-2 pr-2">
                          <div className="mono truncate text-[11.5px] text-text" title={entry.domain}>
                            {entry.domain}
                          </div>
                          <div className="mt-0.5 text-[10px] text-text-3">
                            {entry.lastHitAt ? `最近命中 ${formatRelative(entry.lastHitAt)}` : "尚未命中"}
                          </div>
                          {entry.ipList && entry.ipList.length > 0 ? (
                            <div className="mono mt-0.5 truncate text-[10px] text-text-3">
                              {entry.ipList.join(", ")}
                            </div>
                          ) : null}
                        </td>
                        <td className="py-2 text-center">
                          <Badge tone="neutral">{entry.qtype}</Badge>
                        </td>
                        <td className="num whitespace-nowrap py-2 text-right text-[11.5px] text-text-2">
                          {formatNumber(entry.remainingTtl)}s
                        </td>
                        <td className="num whitespace-nowrap py-2 text-right text-[11.5px] text-text-2">
                          {formatNumber(entry.hitCount)}
                        </td>
                        <td className="py-2 text-right">
                          <Badge tone={status.tone}>{status.label}</Badge>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
