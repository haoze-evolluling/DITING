import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Copy, HardDriveDownload, Save, Upload } from "lucide-react";
import { toast } from "sonner";

import { useCachePersistStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber } from "../../lib/format";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { LoadingState } from "../ui/loading";

export function CachePersistCard() {
  const status = useCachePersistStatus();
  const queryClient = useQueryClient();
  const [confirmLoad, setConfirmLoad] = useState(false);
  const data = status.data;

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["cache-persist"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-stats"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-entries"] });
    void queryClient.invalidateQueries({ queryKey: ["cache-top"] });
  };

  const dump = useMutation({
    mutationFn: api.dumpCache,
    onSuccess: (result) => {
      toast.success(`缓存已落盘，共 ${formatNumber(result.entryCount)} 条`);
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const load = useMutation({
    mutationFn: api.loadCache,
    onSuccess: (result) => {
      toast.success(`已从落盘文件恢复 ${formatNumber(result.restored ?? result.entryCount)} 条缓存`);
      setConfirmLoad(false);
      invalidate();
    },
    onError: (error) => {
      setConfirmLoad(false);
      toast.error(describeError(error));
    },
  });

  const copyPath = () => {
    if (!data?.path) return;
    navigator.clipboard
      .writeText(data.path)
      .then(() => toast.success("缓存文件路径已复制"))
      .catch(() => toast.error("无法访问剪贴板"));
  };

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="落盘与恢复"
        description="手动把内存缓存写入磁盘，或在需要时从落盘文件恢复。"
        actions={
          <Badge tone={data?.persistOn ? "good" : "neutral"} dot>
            {data?.persistOn ? "自动落盘已开启" : "自动落盘已关闭"}
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col gap-3 pt-2">
        {status.isLoading || !data ? (
          <LoadingState label="正在加载落盘状态…" />
        ) : (
          <>
            <div className="rounded-xl border border-border bg-surface-2 px-3 py-2.5">
              <div className="text-[10.5px] text-text-3">缓存文件</div>
              <div className="mt-1 flex items-center gap-2">
                <span className="mono min-w-0 flex-1 break-all text-[11px] text-text-2">
                  {data.path || "—"}
                </span>
                <button
                  type="button"
                  onClick={copyPath}
                  className="shrink-0 rounded p-0.5 text-text-3 hover:text-text"
                  title="复制路径"
                  aria-label="复制缓存文件路径"
                >
                  <Copy className="h-3 w-3" />
                </button>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-2">
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2">
                <div className="text-[10px] text-text-3">当前条目</div>
                <div className="num mt-0.5 text-[15px] font-semibold text-text">
                  {formatNumber(data.entryCount)}
                </div>
              </div>
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2">
                <div className="text-[10px] text-text-3">落盘间隔</div>
                <div className="num mt-0.5 text-[15px] font-semibold text-text">
                  {data.persistOn ? `${formatNumber(data.intervalSec)}s` : "—"}
                </div>
              </div>
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2">
                <div className="text-[10px] text-text-3">排除命中</div>
                <div className="num mt-0.5 text-[15px] font-semibold text-text">
                  {formatNumber(data.excludeHits)}
                </div>
              </div>
            </div>

            {data.excludeRules && data.excludeRules.length > 0 ? (
              <div className="rounded-lg bg-surface-2 px-3 py-2">
                <div className="text-[10.5px] text-text-3">
                  排除规则 {data.excludeRules.length} 条
                </div>
                <div className="mono mt-1 line-clamp-2 break-all text-[10.5px] text-text-2">
                  {data.excludeRules.join(" · ")}
                </div>
              </div>
            ) : null}

            {data.lastError ? (
              <p className="rounded-lg bg-danger-soft px-3 py-2 text-[11px] leading-5 text-danger">
                最近一次落盘失败：{data.lastError}
              </p>
            ) : null}

            <div className="mt-auto flex flex-wrap items-center gap-2">
              <Button
                size="sm"
                variant="secondary"
                loading={dump.isPending}
                onClick={() => dump.mutate()}
              >
                <Save className="h-3.5 w-3.5" />
                立即落盘
              </Button>
              <Button
                size="sm"
                variant="secondary"
                disabled={load.isPending}
                onClick={() => setConfirmLoad(true)}
              >
                <Upload className="h-3.5 w-3.5" />
                从文件恢复
              </Button>
              <span className="ml-auto inline-flex items-center gap-1 text-[10px] text-text-3">
                <HardDriveDownload className="h-3 w-3" />
                {data.persistOn ? "服务会按间隔自动保存" : "仅支持手动保存"}
              </span>
            </div>
          </>
        )}
      </CardContent>

      <ConfirmDialog
        open={confirmLoad}
        onOpenChange={setConfirmLoad}
        title="从落盘文件恢复缓存"
        description="将读取落盘文件并把条目加载到内存缓存，不会修改当前缓存配置。确定继续吗？"
        confirmLabel="恢复"
        tone="primary"
        loading={load.isPending}
        onConfirm={() => load.mutate()}
      />
    </Card>
  );
}
