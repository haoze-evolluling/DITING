import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Network, Save, ShieldCheck, ShieldOff } from "lucide-react";
import { toast } from "sonner";

import { useLanStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { firewallBackendLabel } from "../../lib/labels";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

export function LanServiceCard() {
  const lan = useLanStatus();
  const queryClient = useQueryClient();
  const [allowLAN, setAllowLAN] = useState(false);
  const [configureFirewall, setConfigureFirewall] = useState(true);
  const [initialFirewall, setInitialFirewall] = useState(true);
  const lanKey = lan.data ? String(lan.data.allowLAN) : null;

  useEffect(() => {
    if (lan.data) setAllowLAN(lan.data.allowLAN);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lanKey]);

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["lan-status"] });
    void queryClient.invalidateQueries({ queryKey: ["status"] });
  };

  const save = useMutation({
    mutationFn: () => api.configureLan(allowLAN, configureFirewall),
    onSuccess: () => {
      toast.success(allowLAN ? "局域网 DNS 已开启" : "局域网 DNS 已关闭");
      setInitialFirewall(configureFirewall);
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const firewall = useMutation({
    mutationFn: (enable: boolean) => api.configureLanFirewall(enable),
    onSuccess: (_, enable) => {
      toast.success(enable ? "已放行 53 端口" : "已移除 53 端口防火墙规则");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const data = lan.data;
  const dirty = data
    ? allowLAN !== data.allowLAN || configureFirewall !== initialFirewall
    : false;
  const backendAvailable = Boolean(data?.firewallBackend && data.firewallBackend !== "none");

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="局域网 DNS 服务"
        description="允许路由器与其他终端共享本机的过滤与解析能力。"
        actions={<Network className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {lan.isLoading || !data ? (
          <LoadingState label="正在加载局域网服务配置…" />
        ) : (
          <>
            <SwitchRow
              title="对局域网开放 53 端口"
              description="开启后监听 0.0.0.0 / [::]，关闭后仅本机可解析"
              checked={allowLAN}
              onCheckedChange={setAllowLAN}
            />
            <SwitchRow
              title="同步放行防火墙规则"
              description={
                backendAvailable
                  ? `通过 ${firewallBackendLabel(data.firewallBackend)} 自动维护 53 端口入站规则`
                  : "当前平台没有可用的防火墙后端，需手动放行"
              }
              checked={configureFirewall}
              onCheckedChange={setConfigureFirewall}
              disabled={!backendAvailable}
            />

            <div className="mt-2 grid gap-2 sm:grid-cols-2">
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2.5">
                <div className="text-[10.5px] text-text-3">监听地址</div>
                <div className="mono mt-1 space-y-0.5 text-[10.5px] text-text-2">
                  {data.listenAddresses.length > 0 ? (
                    data.listenAddresses.map((address) => (
                      <div key={address} className="truncate" title={address}>
                        {address}
                      </div>
                    ))
                  ) : (
                    <div>—</div>
                  )}
                </div>
              </div>
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2.5">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[10.5px] text-text-3">防火墙状态</span>
                  <Badge tone={data.firewallAllowed ? "good" : "warn"} dot>
                    {data.firewallAllowed ? "已放行" : "未放行"}
                  </Badge>
                </div>
                <div className="mono mt-1 space-y-0.5 text-[10.5px] text-text-2">
                  {data.lanAddresses.length > 0 ? (
                    data.lanAddresses.map((address) => (
                      <div key={address} className="truncate" title={`${address}:53`}>
                        {address}:53
                      </div>
                    ))
                  ) : (
                    <div className="text-text-3">未检测到局域网地址</div>
                  )}
                </div>
              </div>
            </div>

            {data.lanAddresses.length > 0 && allowLAN ? (
              <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] leading-4 text-text-3">
                路由器或终端可将 DNS 指向
                <span className="mono ml-1 break-all text-text-2">{data.lanAddresses[0]}</span>。修改开关会重启
                DNS 监听器并保持系统接管状态。
              </p>
            ) : null}
          </>
        )}
      </CardContent>
      <CardFooter>
        <Button
          size="sm"
          variant="ghost"
          disabled={!backendAvailable}
          loading={firewall.isPending}
          onClick={() => firewall.mutate(!data?.firewallAllowed)}
        >
          {data?.firewallAllowed ? (
            <ShieldOff className="h-3.5 w-3.5" />
          ) : (
            <ShieldCheck className="h-3.5 w-3.5" />
          )}
          {data?.firewallAllowed ? "移除防火墙规则" : "放行 53 端口"}
        </Button>
        <Button
          size="sm"
          variant="primary"
          disabled={!dirty}
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
