import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { CircleCheck, RefreshCw, TriangleAlert, Wrench } from "lucide-react";

import { useRuntimeActions } from "../../hooks/use-runtime-actions";
import { api, describeError } from "../../lib/api";
import type { StatusResponse } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { ConfirmDialog } from "../ui/confirm-dialog";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { LoadingState } from "../ui/loading";

export function DiagnosticsDialog({
  open,
  onOpenChange,
  status,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  status?: StatusResponse;
}) {
  const actions = useRuntimeActions();
  const [confirmFix, setConfirmFix] = useState(false);

  const check = useQuery({
    queryKey: ["portcheck"],
    queryFn: api.portCheck,
    enabled: open,
    staleTime: 0,
    retry: 0,
  });

  const result = check.data;

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="w-[min(660px,calc(100vw-40px))]">
          <DialogHeader
            title="网络诊断"
            description="检查 53 端口占用、共享服务冲突与本机监听状态。"
          />
          <DialogBody className="space-y-4">
            {check.isLoading ? (
              <LoadingState label="正在执行网络诊断…" className="min-h-[112px]" />
            ) : check.isError ? (
              <div className="rounded-xl border border-danger/25 bg-danger-soft px-3.5 py-3 text-[12px] text-danger">
                {describeError(check.error)}
              </div>
            ) : result?.available ? (
              <div className="flex items-start gap-2.5 rounded-xl border border-good/25 bg-good-soft px-3.5 py-3">
                <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-good" />
                <div>
                  <div className="text-[12.5px] font-medium text-good">53 端口可用</div>
                  <p className="mt-0.5 text-[11.5px] leading-5 text-good/85">
                    当前没有检测到会阻碍 DNS 监听的端口冲突。
                  </p>
                </div>
              </div>
            ) : (
              <>
                <div className="flex items-start gap-2.5 rounded-xl border border-warn/25 bg-warn-soft px-3.5 py-3">
                  <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-warn" />
                  <div className="min-w-0">
                    <div className="text-[12.5px] font-medium text-warn">
                      检测到 {result?.conflicts.length ?? 0} 个端口冲突
                    </div>
                    <p className="mt-0.5 whitespace-pre-wrap text-[11.5px] leading-5 text-warn/85">
                      {result?.diagnostic || "53 端口被其他进程占用，DNS 服务可能无法监听。"}
                    </p>
                  </div>
                </div>

                {(result?.conflicts.length ?? 0) > 0 ? (
                  <div className="overflow-hidden rounded-xl border border-border">
                    <div className="grid grid-cols-[100px_1fr_1fr] gap-3 bg-surface-2 px-3 py-1.5 text-[10.5px] text-text-3">
                      <span>端口</span>
                      <span>本地地址</span>
                      <span>占用进程</span>
                    </div>
                    {result?.conflicts.map((conflict, index) => (
                      <div
                        key={`${conflict.localAddress}-${conflict.protocol}-${index}`}
                        className="grid grid-cols-[100px_1fr_1fr] items-center gap-3 border-t border-border/70 px-3 py-2 text-[11.5px]"
                      >
                        <span className="flex items-center gap-1.5">
                          <span className="num text-text">{conflict.port}</span>
                          <Badge tone="neutral">{conflict.protocol}</Badge>
                        </span>
                        <span className="mono truncate text-text-2">{conflict.localAddress}</span>
                        <span className="truncate text-text-2">
                          {conflict.processName || "未知进程"}
                          {conflict.pid ? <span className="text-text-3"> (PID {conflict.pid})</span> : null}
                          {conflict.isSelf ? (
                            <Badge tone="accent" className="ml-1.5">
                              本服务
                            </Badge>
                          ) : null}
                        </span>
                      </div>
                    ))}
                  </div>
                ) : null}
              </>
            )}
          </DialogBody>
          <DialogFooter>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => void check.refetch()}
              loading={check.isFetching}
            >
              <RefreshCw className="h-3.5 w-3.5" />
              重新检测
            </Button>
            {result && !result.available && result.canAutofix ? (
              <Button size="sm" variant="secondary" onClick={() => setConfirmFix(true)}>
                <Wrench className="h-3.5 w-3.5" />
                自动修复
              </Button>
            ) : null}
            <Button size="sm" variant="primary" onClick={() => onOpenChange(false)}>
              完成
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={confirmFix}
        onOpenChange={setConfirmFix}
        title="自动修复端口冲突"
        description="修复过程可能停止占用 53 端口的共享服务（例如 Windows 网络连接共享），并在完成后重新检测端口。网络可能短暂中断。"
        confirmLabel="开始修复"
        tone="primary"
        loading={actions.portAutofix.isPending}
        onConfirm={() =>
          actions.portAutofix.mutate(status?.dns.running ?? false, {
            onSuccess: () => {
              setConfirmFix(false);
              void check.refetch();
            },
          })
        }
      />
    </>
  );
}
