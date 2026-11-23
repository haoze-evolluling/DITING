import { useMemo, useState } from "react";
import { RefreshCw, Settings2 } from "lucide-react";
import { NavLink } from "react-router-dom";

import { TrafficChart } from "../components/charts/traffic-chart";
import { LogSummary } from "../components/logs/log-summary";
import { LogToolbar, type LogFilters } from "../components/logs/log-toolbar";
import { QueryDetailSheet } from "../components/logs/query-detail-sheet";
import { QueryTable } from "../components/logs/query-table";
import { TopLists } from "../components/logs/top-lists";
import { PageHeader } from "../components/layout/page-header";
import { Button } from "../components/ui/button";
import { Card, CardFooter } from "../components/ui/card";
import { ConfirmDialog } from "../components/ui/confirm-dialog";
import { useQueryLogSearch, useQueryStats } from "../hooks/use-api";
import { useRuntimeActions } from "../hooks/use-runtime-actions";
import { formatNumber } from "../lib/format";
import type { QueryRecord } from "../lib/types";
import { useLiveStore } from "../stores/live";

const PAGE_SIZE = 100;
const emptyFilters: LogFilters = { domain: "", client: "", status: "", qtype: "" };

function liveMatches(record: QueryRecord, filters: LogFilters): boolean {
  const domain = filters.domain.trim().toLowerCase();
  if (domain && !record.domain.toLowerCase().includes(domain)) return false;
  const client = filters.client.trim().toLowerCase();
  if (client) {
    const haystack = `${record.clientIP ?? ""} ${record.clientName ?? ""}`.toLowerCase();
    if (!haystack.includes(client)) return false;
  }
  if (filters.status && record.status !== filters.status) return false;
  if (filters.qtype && (record.qtype ?? "").toUpperCase() !== filters.qtype.toUpperCase()) {
    return false;
  }
  return true;
}

export function LogsPage() {
  const stats = useQueryStats();
  const liveQueries = useLiveStore((state) => state.queries);
  const connected = useLiveStore((state) => state.connected);
  const actions = useRuntimeActions();

  const [filters, setFilters] = useState<LogFilters>(emptyFilters);
  const [applied, setApplied] = useState<LogFilters>(emptyFilters);
  const [page, setPage] = useState(0);
  const [live, setLive] = useState(false);
  const [selected, setSelected] = useState<QueryRecord | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);

  const search = useQueryLogSearch(
    { ...applied, limit: PAGE_SIZE, offset: page * PAGE_SIZE },
    !live,
  );

  const filteredLive = useMemo(
    () => liveQueries.filter((record) => liveMatches(record, filters)),
    [liveQueries, filters],
  );

  const rows = live ? filteredLive : search.data?.entries ?? [];
  const total = live ? filteredLive.length : search.data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const submit = () => {
    setApplied(filters);
    setPage(0);
    setLive(false);
  };

  const reset = () => {
    setFilters(emptyFilters);
    setApplied(emptyFilters);
    setPage(0);
    setLive(false);
  };

  return (
    <>
      <PageHeader
        title="查询日志"
        description="实时请求、历史检索与最近 24 小时统计"
        actions={
          <>
            <Button
              size="sm"
              variant="ghost"
              asChild
            >
              <NavLink to="/settings">
                <Settings2 className="h-3.5 w-3.5" />
                日志设置
              </NavLink>
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                void stats.refetch();
                void search.refetch();
              }}
              loading={stats.isFetching}
            >
              <RefreshCw className="h-3.5 w-3.5" />
              刷新
            </Button>
          </>
        }
      />

      <div className="space-y-3.5">
        <TrafficChart
          points={stats.data?.perHour ?? []}
          loading={stats.isLoading}
          title="查询趋势"
          description="最近 24 小时的查询、拦截与缓存命中"
        />

        <div className="card-grid-2">
          <LogSummary stats={stats.data} loading={stats.isLoading} />
          <TopLists stats={stats.data} loading={stats.isLoading} />
        </div>

        <div className="min-w-0 space-y-3.5">
          <LogToolbar
            filters={filters}
            onChange={(patch) => setFilters((current) => ({ ...current, ...patch }))}
            live={live}
            onLiveChange={(next) => {
              setLive(next);
              if (next) setPage(0);
            }}
            onSubmit={submit}
            onReset={reset}
            onClear={() => setConfirmClear(true)}
            clearing={actions.clearQueryLog.isPending}
          />

          <Card className="overflow-hidden">
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-2.5">
              <div className="flex items-center gap-2 text-[12px] text-text-2">
                <span
                  className={`h-1.5 w-1.5 rounded-full ${
                    live && connected ? "bg-good" : "bg-text-3"
                  }`}
                />
                {live ? "实时查询流" : "历史查询结果"}
                <span className="text-text-3">共 {formatNumber(total)} 条</span>
              </div>
              <span className="text-[10.5px] text-text-3">
                {live
                  ? "仅保留本次会话最近 400 条"
                  : `第 ${Math.min(page + 1, pages)} / ${pages} 页 · 每页 ${PAGE_SIZE} 条`}
              </span>
            </div>

            <QueryTable
              rows={rows}
              loading={!live && search.isLoading}
              live={live}
              onSelect={setSelected}
            />

            {!live ? (
              <CardFooter className="bg-surface-2/60">
                <span className="text-[10.5px] text-text-3">
                  数据来源包含内存与 SQLite 数据库中的查询日志
                </span>
                <div className="flex items-center gap-1.5">
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={page === 0 || search.isFetching}
                    onClick={() => setPage((current) => Math.max(current - 1, 0))}
                  >
                    上一页
                  </Button>
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={page + 1 >= pages || search.isFetching}
                    onClick={() => setPage((current) => current + 1)}
                  >
                    下一页
                  </Button>
                </div>
              </CardFooter>
            ) : null}
          </Card>
        </div>
      </div>

      <QueryDetailSheet
        record={selected}
        open={selected !== null}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      />

      <ConfirmDialog
        open={confirmClear}
        onOpenChange={setConfirmClear}
        title="清空查询日志"
        description="将删除内存中的查询记录与统计，并清理数据库中的日志。此操作不可撤销。"
        confirmLabel="清空日志"
        loading={actions.clearQueryLog.isPending}
        onConfirm={() =>
          actions.clearQueryLog.mutate(undefined, {
            onSuccess: () => {
              setConfirmClear(false);
              setPage(0);
              void search.refetch();
            },
          })
        }
      />
    </>
  );
}
