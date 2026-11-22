import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Database, Recycle, RefreshCw, Target, Trash2, Zap } from "lucide-react";
import { toast } from "sonner";

import { CacheConfigCard } from "../components/cache/cache-config-card";
import { CacheEntriesCard } from "../components/cache/cache-entries-card";
import { CachePersistCard } from "../components/cache/cache-persist-card";
import { CacheTopCard } from "../components/cache/cache-top-card";
import { PageHeader } from "../components/layout/page-header";
import { Button } from "../components/ui/button";
import { ConfirmDialog } from "../components/ui/confirm-dialog";
import { StatTile } from "../components/ui/stat-tile";
import { useCacheStats } from "../hooks/use-api";
import { api, describeError } from "../lib/api";
import { formatNumber, formatRatio } from "../lib/format";

export function CachePage() {
  const stats = useCacheStats();
  const queryClient = useQueryClient();
  const [confirmClear, setConfirmClear] = useState(false);
  const data = stats.data;

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["cache-stats"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-entries"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-top"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-persist"] });
    void queryClient.invalidateQueries({ queryKey: ["status"] });
  };

  const clear = useMutation({
    mutationFn: api.clearCache,
    onSuccess: () => {
      toast.success("智能缓存已清空");
      setConfirmClear(false);
      invalidate();
    },
    onError: (error) => {
      setConfirmClear(false);
      toast.error(describeError(error));
    },
  });

  const refresh = () => {
    void queryClient.invalidateQueries();
  };

  return (
    <>
      <PageHeader
        title="解析缓存"
        description="命中统计、缓存条目、策略与落盘持久化"
        actions={
          <>
            <Button size="sm" variant="ghost" onClick={refresh} loading={stats.isFetching}>
              <RefreshCw className="h-3.5 w-3.5" />
              刷新
            </Button>
            <Button
              size="sm"
              variant="dangerSoft"
              disabled={!data?.entryCount}
              onClick={() => setConfirmClear(true)}
            >
              <Trash2 className="h-3.5 w-3.5" />
              清空缓存
            </Button>
          </>
        }
      />

      <div className="space-y-3.5">
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <StatTile
            label="缓存条目"
            value={formatNumber(data?.entryCount)}
            hint={`容量 ${formatNumber(data?.maxEntries)} • ${
              data?.enabled ? "缓存已启用" : "缓存已关闭"
            }`}
            icon={Database}
            tone="accent"
            loading={stats.isLoading}
          />
          <StatTile
            label="缓存命中率"
            value={formatRatio(data?.hitRatio)}
            hint={`${formatNumber(data?.totalHits)} 命中 · ${formatNumber(data?.totalMisses)} 未命中`}
            icon={Target}
            tone="good"
            loading={stats.isLoading}
          />
          <StatTile
            label="特殊命中"
            value={formatNumber((data?.staleHits ?? 0) + (data?.negativeHits ?? 0))}
            hint={`过期 ${formatNumber(data?.staleHits)} · 否定 ${formatNumber(
              data?.negativeHits,
            )}`}
            icon={Zap}
            tone="violet"
            loading={stats.isLoading}
          />
          <StatTile
            label="淘汰与预取"
            value={formatNumber(data?.evictionCount)}
            hint={`预取 ${formatNumber(data?.prefetchCount)} 次`}
            icon={Recycle}
            tone="neutral"
            loading={stats.isLoading}
          />
        </div>

        <div className="grid gap-3.5 xl:grid-cols-[1.15fr_1fr]">
          <CacheEntriesCard />
          <CacheTopCard />
        </div>

        <div className="grid gap-3.5 xl:grid-cols-[1.25fr_1fr]">
          <CacheConfigCard />
          <CachePersistCard />
        </div>
      </div>

      <ConfirmDialog
        open={confirmClear}
        onOpenChange={setConfirmClear}
        title="清空智能缓存"
        description="将删除内存中的全部缓存条目，后续查询会重新向上游解析。确定继续吗？"
        confirmLabel="清空"
        loading={clear.isPending}
        onConfirm={() => clear.mutate()}
      />
    </>
  );
}
