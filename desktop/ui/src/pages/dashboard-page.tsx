import { useState } from "react";
import { RefreshCw } from "lucide-react";

import { TrafficChart } from "../components/charts/traffic-chart";
import { DiagnosticsDialog } from "../components/dashboard/diagnostics-dialog";
import { HeroStatus } from "../components/dashboard/hero-status";
import { RecentQueries } from "../components/dashboard/recent-queries";
import { StatGrid } from "../components/dashboard/stat-grid";
import { TakeoverCard } from "../components/dashboard/takeover-card";
import { UpstreamsCard } from "../components/dashboard/upstreams-card";
import { PageHeader } from "../components/layout/page-header";
import { Button } from "../components/ui/button";
import { useQueryLogSearch, useQueryStats, useStatus } from "../hooks/use-api";
import { useRuntimeActions } from "../hooks/use-runtime-actions";
import { useLiveStore } from "../stores/live";

export function DashboardPage() {
  const status = useStatus();
  const stats = useQueryStats();
  const liveMetrics = useLiveStore((state) => state.metrics);
  const liveQueries = useLiveStore((state) => state.queries);
  const connected = useLiveStore((state) => state.connected);
  const history = useQueryLogSearch({ limit: 7 }, liveQueries.length === 0);
  const recent = liveQueries.length > 0 ? liveQueries : history.data?.entries ?? [];
  const actions = useRuntimeActions();
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);

  const running = status.data?.dns.running ?? false;
  const takeoverActive = status.data?.takeover.active ?? false;
  const busy =
    actions.startDns.isPending ||
    actions.stopDns.isPending ||
    actions.enableTakeover.isPending ||
    actions.disableTakeover.isPending;

  const toggleDns = () => {
    if (running) {
      // 先还原系统 DNS 再停止解析：还原失败时中止停止操作，
      // 避免网卡继续指向已经停止的本地解析服务。
      if (takeoverActive) {
        actions.disableTakeover.mutate(undefined, {
          onSuccess: () => actions.stopDns.mutate(),
        });
        return;
      }
      actions.stopDns.mutate();
      return;
    }

    // 启动解析成功后自动接管系统 DNS；接管失败只提示，不影响已启动的 DNS。
    actions.startDns.mutate(undefined, {
      onSuccess: () => {
        if (!takeoverActive) actions.enableTakeover.mutate();
      },
    });
  };

  const refresh = () => {
    void status.refetch();
    void stats.refetch();
  };

  return (
    <>
      <PageHeader
        title="概览"
        description="本机 DNS 过滤、系统接管与实时运行状态"
        actions={
          <Button
            size="sm"
            variant="ghost"
            onClick={refresh}
            loading={status.isFetching}
          >
            <RefreshCw className="h-3.5 w-3.5" />
            刷新
          </Button>
        }
      />

      <div className="space-y-3.5">
        <div className="card-grid-2">
          <HeroStatus
            status={status.data}
            metrics={liveMetrics}
            loading={status.isLoading}
            busy={busy}
            onToggleDns={toggleDns}
            onOpenDiagnostics={() => setDiagnosticsOpen(true)}
          />
          <TrafficChart
            points={stats.data?.perHour ?? []}
            loading={stats.isLoading}
            className="min-h-[248px]"
          />
        </div>

        <StatGrid
          status={status.data}
          metrics={liveMetrics}
          loading={status.isLoading}
        />

        <div className="card-grid-2">
          <UpstreamsCard
            status={status.data}
            stats={stats.data}
            loading={status.isLoading}
          />
          <TakeoverCard status={status.data} loading={status.isLoading} />
        </div>

        <RecentQueries
          queries={recent}
          connected={connected}
          live={liveQueries.length > 0}
        />
      </div>

      <DiagnosticsDialog
        open={diagnosticsOpen}
        onOpenChange={setDiagnosticsOpen}
        status={status.data}
      />
    </>
  );
}
