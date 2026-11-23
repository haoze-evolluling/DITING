import { useState } from "react";
import { Network, ShieldCheck, ShieldOff, TriangleAlert } from "lucide-react";

import { useAdapters, useServiceStatus } from "../../hooks/use-api";
import { useRuntimeActions } from "../../hooks/use-runtime-actions";
import { adapterStatusLabel } from "../../lib/labels";
import type { StatusResponse } from "../../lib/types";
import { cn } from "../../lib/cn";
import { ListRowsSkeleton } from "../skeletons/parts";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { EmptyState } from "../ui/empty";
import { Switch } from "../ui/switch";
import { Hint } from "../ui/tooltip";

export function TakeoverCard({
  status,
  loading,
}: {
  status?: StatusResponse;
  loading: boolean;
}) {
  const adapters = useAdapters();
  const service = useServiceStatus();
  const actions = useRuntimeActions();
  const [confirmRestore, setConfirmRestore] = useState(false);

  const takeover = status?.takeover;
  const active = takeover?.active ?? false;
  const activeIds = new Set((takeover?.adapters ?? []).map((adapter) => adapter.id));
  const physical = (adapters.data ?? []).filter((adapter) => adapter.isPhysical);
  const globalPending = actions.enableTakeover.isPending || actions.disableTakeover.isPending;
  const notElevated = service.data ? !service.data.isElevated : false;

  const toggleGlobal = (next: boolean) => {
    if (next) actions.enableTakeover.mutate();
    else actions.disableTakeover.mutate();
  };

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="系统 DNS 接管"
        description="把物理网卡的 DNS 指向本机谛听服务"
        actions={
          <div className="flex items-center gap-2">
            <span className="text-[11px] text-text-3">{active ? "已接管" : "未接管"}</span>
            <Switch
              checked={active}
              onCheckedChange={toggleGlobal}
              disabled={globalPending || loading}
              label="切换系统 DNS 接管"
            />
          </div>
        }
      />
      <CardContent className="flex-1 pt-2">
        {notElevated ? (
          <div className="mb-3 flex items-start gap-2 rounded-lg bg-warn-soft px-3 py-2 text-[11.5px] leading-5 text-warn">
            <TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            当前服务进程未以管理员权限运行，接管网卡可能失败。请安装为系统服务或以管理员身份启动。
          </div>
        ) : null}

        {adapters.isLoading || loading ? (
          <ListRowsSkeleton rows={2} />
        ) : physical.length === 0 ? (
          <EmptyState
            icon={Network}
            title="未发现物理网卡"
            description="确认网络适配器已启用后重新检测。"
          />
        ) : (
          <div className="divide-y divide-border/70">
            {physical.map((adapter) => {
              const checked = activeIds.has(adapter.id);
              const pending =
                actions.setAdapterTakeover.isPending &&
                actions.setAdapterTakeover.variables?.adapterId === adapter.id;
              return (
                <div key={adapter.id} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-[12.5px] font-medium text-text">
                        {adapter.name}
                      </span>
                      <Badge tone={adapter.status.toLowerCase() === "up" ? "good" : "neutral"}>
                        {adapterStatusLabel(adapter.status)}
                      </Badge>
                    </div>
                    <div className="mt-0.5 truncate text-[10.5px] text-text-3">
                      {adapter.description}
                      {adapter.gateway ? <span className="mono"> · 网关 {adapter.gateway}</span> : null}
                    </div>
                    <div className="mono mt-0.5 truncate text-[10px] text-text-3">
                      DNS {adapter.ipv4DNS.length > 0 ? adapter.ipv4DNS.join(", ") : "自动获取"}
                    </div>
                  </div>
                  <Hint content={checked ? "还原此网卡 DNS" : "接管此网卡 DNS"}>
                    <span>
                      <Switch
                        checked={checked}
                        onCheckedChange={(enable) =>
                          actions.setAdapterTakeover.mutate({ adapterId: adapter.id, enable })
                        }
                        disabled={pending}
                        label={`切换 ${adapter.name} 的 DNS 接管`}
                      />
                    </span>
                  </Hint>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
      <CardFooter>
        <span className="flex items-center gap-1.5 text-[10.5px] text-text-3">
          {active ? (
            <>
              <ShieldCheck className="h-3.5 w-3.5 text-good" />
              服务异常退出时会自动还原网卡 DNS
            </>
          ) : (
            <>
              <ShieldOff className="h-3.5 w-3.5" />
              接管前请确认本机解析服务运行正常
            </>
          )}
        </span>
        <Button
          size="sm"
          variant="dangerSoft"
          className={cn("shrink-0")}
          onClick={() => setConfirmRestore(true)}
        >
          紧急恢复
        </Button>
      </CardFooter>

      <ConfirmDialog
        open={confirmRestore}
        onOpenChange={setConfirmRestore}
        title="紧急恢复系统 DNS"
        description="将清理由谛听写入的 DNS 配置并还原网卡的原始设置。网络可能短暂中断，请确认当前没有依赖谛听解析的服务。"
        confirmLabel="立即恢复"
        loading={actions.emergencyRestore.isPending}
        onConfirm={() =>
          actions.emergencyRestore.mutate(undefined, {
            onSuccess: () => setConfirmRestore(false),
          })
        }
      />
    </Card>
  );
}
