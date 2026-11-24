import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Router, Save, ShieldCheck, ShieldOff } from "lucide-react";
import { toast } from "sonner";

import { useOpenWrtStatus } from "../../hooks/use-api";
import { useRuntimeActions } from "../../hooks/use-runtime-actions";
import { api, describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import type { OpenWrtTakeoverMode, StatusResponse } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { Switch } from "../ui/switch";
import { SwitchRow } from "../ui/switch-row";

export function OpenWrtTakeoverCard({
  status,
  loading,
}: {
  status?: StatusResponse;
  loading: boolean;
}) {
  const openwrt = useOpenWrtStatus(true);
  const actions = useRuntimeActions();
  const queryClient = useQueryClient();
  const [confirmRestore, setConfirmRestore] = useState(false);

  const [mode, setMode] = useState<OpenWrtTakeoverMode>("replace_dnsmasq");
  const [dnsmasqPort, setDnsmasqPort] = useState(5353);
  const [upstreamPort, setUpstreamPort] = useState(5354);
  const [forwardLocalDomain, setForwardLocalDomain] = useState(true);
  const [forceRedirect53, setForceRedirect53] = useState(false);

  const data = openwrt.data;
  const syncKey = JSON.stringify(
    data
      ? {
          mode: data.mode,
          dnsmasqPort: data.dnsmasqPort,
          upstreamPort: data.upstreamPort,
          forwardLocalDomain: data.forwardLocalDomain,
          forceRedirect53: data.forceRedirect53,
        }
      : null,
  );

  useEffect(() => {
    if (!data) return;
    setMode(
      data.mode === "dnsmasq_upstream" ? "dnsmasq_upstream" : "replace_dnsmasq",
    );
    setDnsmasqPort(data.dnsmasqPort || 5353);
    setUpstreamPort(data.upstreamPort || 5354);
    setForwardLocalDomain(data.forwardLocalDomain);
    setForceRedirect53(data.forceRedirect53);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [syncKey]);

  const active = Boolean(data?.active ?? status?.takeover.active);
  const isReplace = mode === "replace_dnsmasq";
  const activePort = isReplace ? dnsmasqPort : upstreamPort;
  const validPort = activePort >= 1024 && activePort <= 65535 && activePort !== 53;

  const dirty = useMemo(() => {
    if (!data) return false;
    return (
      mode !== data.mode ||
      dnsmasqPort !== data.dnsmasqPort ||
      upstreamPort !== data.upstreamPort ||
      forwardLocalDomain !== data.forwardLocalDomain ||
      forceRedirect53 !== data.forceRedirect53
    );
  }, [data, mode, dnsmasqPort, upstreamPort, forwardLocalDomain, forceRedirect53]);

  const invalidateAll = () => {
    void queryClient.invalidateQueries({ queryKey: ["openwrt-status"] });
    void queryClient.invalidateQueries({ queryKey: ["status"] });
    void queryClient.invalidateQueries({ queryKey: ["lan-status"] });
  };

  const save = useMutation({
    mutationFn: () =>
      api.configureOpenwrt({
        mode,
        dnsmasqPort,
        upstreamPort,
        forwardLocalDomain,
        forceRedirect53,
      }),
    onSuccess: () => {
      toast.success("OpenWrt DNS 协同配置已保存");
      invalidateAll();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const globalPending =
    actions.startDns.isPending ||
    actions.stopDns.isPending ||
    actions.enableTakeover.isPending ||
    actions.disableTakeover.isPending;

  const toggleActive = (next: boolean) => {
    if (next) {
      actions.enableTakeover.mutate(undefined, { onSuccess: invalidateAll });
    } else {
      actions.disableTakeover.mutate(undefined, { onSuccess: invalidateAll });
    }
  };

  const localDomain = data?.localDomain || "lan";

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="路由器 DNS 接管"
        description="与 OpenWrt 原生 dnsmasq 协同接管局域网解析"
        actions={
          <div className="flex items-center gap-2">
            <span className="text-[11px] text-text-3">{active ? "已接管" : "未接管"}</span>
            <Switch
              checked={active}
              onCheckedChange={toggleActive}
              disabled={globalPending || loading || openwrt.isLoading}
              label="切换路由器 DNS 接管"
            />
          </div>
        }
      />
      <CardContent className="flex-1 space-y-2.5 pt-1">
        {openwrt.isLoading || !data ? (
          <LoadingState label="正在读取 OpenWrt 集成状态…" className="min-h-[140px]" />
        ) : (
          <>
            <div className="grid grid-cols-2 gap-1.5 rounded-xl border border-border bg-surface-2 p-1">
              {[
                {
                  id: "replace_dnsmasq" as const,
                  title: "接管 53 端口",
                  hint: "保留真实终端 IP 与分组",
                },
                {
                  id: "dnsmasq_upstream" as const,
                  title: "作为 dnsmasq 上游",
                  hint: "兼容依赖 dnsmasq 的插件",
                },
              ].map((option) => {
                const selected = mode === option.id;
                return (
                  <button
                    key={option.id}
                    type="button"
                    onClick={() => setMode(option.id)}
                    className={cn(
                      "rounded-lg px-2.5 py-1.5 text-left transition-colors",
                      selected
                        ? "bg-surface text-text shadow-xs ring-1 ring-border-strong"
                        : "text-text-3 hover:text-text-2",
                    )}
                  >
                    <div className="flex items-center justify-between gap-1 text-[11.5px] font-medium">
                      <span className="truncate">{option.title}</span>
                      {option.id === "replace_dnsmasq" ? (
                        <Badge tone={selected ? "accent" : "neutral"}>推荐</Badge>
                      ) : null}
                    </div>
                    <div className="mt-0.5 truncate text-[10px] text-text-3">
                      {option.hint}
                    </div>
                  </button>
                );
              })}
            </div>

            <div className="grid gap-2.5 sm:grid-cols-2">
              <label className="block">
                <span className="text-[11.5px] text-text-2">
                  {isReplace ? "dnsmasq 辅端口" : "谛听本地转发端口"}
                </span>
                <Input
                  className="mt-1"
                  type="number"
                  min={1024}
                  max={65535}
                  value={activePort}
                  onChange={(event) => {
                    const next = Number(event.target.value);
                    if (isReplace) setDnsmasqPort(next);
                    else setUpstreamPort(next);
                  }}
                />
                <span className="mt-0.5 block text-[10px] text-text-3">
                  {isReplace
                    ? "迁移后仍由 dnsmasq 负责 DHCP"
                    : `UCI 上游指向 127.0.0.1#${upstreamPort}`}
                </span>
              </label>

              <div className="flex flex-col justify-between rounded-xl border border-border bg-surface-2 px-3 py-2">
                <div className="flex items-center justify-between gap-1.5">
                  <span className="flex items-center gap-1 text-[10.5px] text-text-3">
                    <Router className="h-3 w-3" />
                    当前链路
                  </span>
                  <Badge tone={active ? "good" : "neutral"} dot>
                    {active ? "常驻生效" : "待机"}
                  </Badge>
                </div>
                <div className="mono mt-1 truncate text-[10.5px] text-text-2">
                  {isReplace
                    ? `0.0.0.0:53 → 谛听 · .${localDomain} → :${dnsmasqPort}`
                    : `dnsmasq :53 → 127.0.0.1:${upstreamPort}`}
                </div>
                <div className="mt-0.5 truncate text-[10px] text-text-3">
                  DHCP 租约主机名自动同步已启用
                </div>
              </div>
            </div>

            {isReplace ? (
              <SwitchRow
                title={`回流内网域名 (.${localDomain}) 与反向 PTR`}
                description="局域网主机名查询自动转发回 dnsmasq，不发往公网上游"
                checked={forwardLocalDomain}
                onCheckedChange={setForwardLocalDomain}
              />
            ) : null}

            <SwitchRow
              title="强制重定向局域网 53 端口（DNAT）"
              description="通过 UCI 防火墙拦截终端硬编码的外部明文 DNS 请求"
              checked={forceRedirect53}
              onCheckedChange={setForceRedirect53}
            />
          </>
        )}
      </CardContent>

      <CardFooter>
        <span className="flex items-center gap-1.5 text-[10.5px] text-text-3">
          {active ? (
            <>
              <ShieldCheck className="h-3.5 w-3.5 text-good" />
              断电重启自动恢复，停止或卸载自动回退 dnsmasq
            </>
          ) : (
            <>
              <ShieldOff className="h-3.5 w-3.5" />
              {dirty ? "存在未保存修改" : "开启后自动接管路由器解析"}
            </>
          )}
        </span>
        <div className="flex shrink-0 items-center gap-1.5">
          <Button
            size="sm"
            variant="dangerSoft"
            onClick={() => setConfirmRestore(true)}
          >
            紧急恢复
          </Button>
          {dirty ? (
            <Button
              size="sm"
              variant="primary"
              disabled={!validPort}
              loading={save.isPending}
              onClick={() => save.mutate()}
            >
              <Save className="h-3.5 w-3.5" />
              保存
            </Button>
          ) : null}
        </div>
      </CardFooter>

      <ConfirmDialog
        open={confirmRestore}
        onOpenChange={setConfirmRestore}
        title="还原 OpenWrt 默认 DNS"
        description="将立即停止谛听接管，通过 UCI 把 dnsmasq 恢复至原始 53 端口并移除 DNAT 重定向规则。"
        confirmLabel="立即恢复"
        loading={actions.emergencyRestore.isPending}
        onConfirm={() =>
          actions.emergencyRestore.mutate(undefined, {
            onSuccess: () => {
              setConfirmRestore(false);
              invalidateAll();
            },
          })
        }
      />
    </Card>
  );
}
