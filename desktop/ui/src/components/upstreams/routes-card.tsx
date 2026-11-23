import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Route, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import type { ProviderConfig } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { Input } from "../ui/input";
import { ListRowsSkeleton } from "../skeletons/parts";

interface RouteRow {
  id: string;
  domain: string;
  upstream: string;
}

let rowCounter = 0;

function newRow(): RouteRow {
  rowCounter += 1;
  return { id: `route-${Date.now()}-${rowCounter}`, domain: "", upstream: "" };
}

function normalizeRouteDomain(value: string): string {
  return value
    .trim()
    .replace(/^\*+/, "")
    .replace(/^\.+|\.+$/g, "")
    .toLowerCase();
}

function rowsToRecord(rows: RouteRow[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const row of rows) {
    const domain = normalizeRouteDomain(row.domain);
    const upstream = row.upstream.trim();
    if (!domain || !upstream) continue;
    out[domain] = upstream;
  }
  return out;
}

function normalizeRecord(input: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [pattern, upstream] of Object.entries(input)) {
    const domain = normalizeRouteDomain(pattern);
    const target = upstream.trim();
    if (!domain || !target) continue;
    out[domain] = target;
  }
  return out;
}

function canonical(record: Record<string, string>): string {
  return JSON.stringify(Object.entries(record).sort(([left], [right]) => left.localeCompare(right)));
}

function suggestUpstream(provider: ProviderConfig): string {
  const protocol = (provider.protocol ?? "").toUpperCase();
  if (protocol === "DOH") return (provider.url || provider.server).trim();
  if (protocol === "DOT") {
    const server = provider.server.trim();
    return server ? (server.startsWith("tls://") ? server : `tls://${server}`) : "";
  }
  return (provider.server || provider.url).trim();
}

export function RoutesCard({
  routes,
  providers,
  loading,
}: {
  routes?: Record<string, string>;
  providers: ProviderConfig[];
  loading: boolean;
}) {
  const queryClient = useQueryClient();
  const [rows, setRows] = useState<RouteRow[]>([]);
  const configKey = JSON.stringify(routes ?? null);

  useEffect(() => {
    if (!routes) return;
    setRows(
      Object.entries(routes)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([domain, upstream], index) => ({
          id: `route-${index}`,
          domain: normalizeRouteDomain(domain),
          upstream,
        })),
    );
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const suggestions = useMemo(() => {
    const values = new Set<string>();
    for (const provider of providers) {
      const value = suggestUpstream(provider);
      if (value) values.add(value);
    }
    return [...values];
  }, [providers]);

  const problems = useMemo(() => {
    const out: string[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      const domain = normalizeRouteDomain(row.domain);
      const upstream = row.upstream.trim();
      if (!domain && !upstream) continue;
      if (!domain || !upstream) {
        out.push("每条规则都需要填写匹配域名与目标 DNS 地址");
        continue;
      }
      if (/[\s/:*]/.test(domain)) {
        out.push(`匹配域名不合法：${row.domain.trim()}`);
        continue;
      }
      if (/^quic:\/\//.test(upstream) || /^doq:\/\//.test(upstream)) {
        out.push(`暂不支持 DoQ 目标：${domain}`);
        continue;
      }
      if (seen.has(domain)) {
        out.push(`匹配域名重复：${domain}`);
        continue;
      }
      seen.add(domain);
    }
    return [...new Set(out)];
  }, [rows]);

  const record = useMemo(() => rowsToRecord(rows), [rows]);
  const dirty = canonical(record) !== canonical(normalizeRecord(routes ?? {}));
  const valid = problems.length === 0;

  const save = useMutation({
    mutationFn: () => api.configureUpstream({ conditionalRoutes: record }),
    onSuccess: () => {
      setRows(
        Object.entries(record)
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([domain, upstream], index) => ({
            id: `route-${index}`,
            domain,
            upstream,
          })),
      );
      toast.success("条件分流路由已更新");
      void queryClient.invalidateQueries({ queryKey: ["upstream-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (id: string, patch: Partial<RouteRow>) =>
    setRows((current) => current.map((row) => (row.id === id ? { ...row, ...patch } : row)));

  const addRow = () => setRows((current) => [...current, newRow()]);

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="条件分流路由"
        description="为内部私有域名定向指定专用 DNS 服务器，支持 *.internal 这类泛域名。"
        actions={
          <Button size="sm" variant="secondary" onClick={addRow} disabled={loading}>
            <Plus className="h-3.5 w-3.5" />
            添加分流规则
          </Button>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {loading ? (
          <ListRowsSkeleton rows={2} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={Route}
            title="暂无分流规则"
            description="全部域名请求遵循全局调度模式。"
            action={
              <Button size="sm" variant="primary" onClick={addRow}>
                <Plus className="h-3.5 w-3.5" />
                添加分流规则
              </Button>
            }
          />
        ) : (
          <div className="space-y-2">
            {rows.map((row) => (
              <div
                key={row.id}
                className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)_auto] items-center gap-2"
              >
                <Input
                  className="mono"
                  value={row.domain}
                  placeholder="*.internal"
                  aria-label="匹配域名或后缀"
                  onChange={(event) => update(row.id, { domain: event.target.value })}
                />
                <Input
                  className="mono"
                  value={row.upstream}
                  list="route-upstream-options"
                  placeholder="tls://192.168.1.1:853"
                  aria-label="定向 DNS 服务器地址"
                  onChange={(event) => update(row.id, { upstream: event.target.value })}
                />
                <Button
                  size="icon"
                  variant="ghost"
                  aria-label="删除分流规则"
                  onClick={() =>
                    setRows((current) => current.filter((item) => item.id !== row.id))
                  }
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}
            <datalist id="route-upstream-options">
              {suggestions.map((value) => (
                <option key={value} value={value} />
              ))}
            </datalist>
          </div>
        )}

        {problems.length > 0 ? (
          <div className="mt-3 space-y-1 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
            {problems.map((problem) => (
              <p key={problem}>{problem}</p>
            ))}
          </div>
        ) : null}

        <p className="mt-3 text-[10.5px] leading-4 text-text-3">
          目标地址支持 1.1.1.1:53、tls:// 与 https://（DoH）；匹配按域名后缀生效，越具体越优先。
        </p>
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {dirty ? "存在未保存的修改" : "配置已与运行服务同步"}
        </span>
        <Button
          size="sm"
          variant="primary"
          disabled={!dirty || !valid}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          <Save className="h-3.5 w-3.5" />
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
