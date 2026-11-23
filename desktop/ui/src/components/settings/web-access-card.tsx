import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Copy, ExternalLink, Save, ShieldCheck, Wifi } from "lucide-react";
import { toast } from "sonner";

import { useWebStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { FieldGridSkeleton, SwitchRowsSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

function isLanListen(address: string): boolean {
  if (!address) return false;
  const host = address.startsWith("[")
    ? address.slice(1, address.indexOf("]"))
    : address.split(":")[0];
  return host !== "" && host !== "127.0.0.1" && host !== "::1" && host !== "localhost";
}

export function WebAccessCard() {
  const web = useWebStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [port, setPort] = useState(15353);
  const [configureFirewall, setConfigureFirewall] = useState(true);
  const data = web.data;
  const lanEnabled = data ? isLanListen(data.listenAddress) : false;
  const configKey = JSON.stringify(
    data ? { listen: data.listenAddress, port: data.port } : null,
  );

  useEffect(() => {
    if (!data) return;
    setEnabled(isLanListen(data.listenAddress));
    setPort(data.port);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(
    () => Boolean(data) && (enabled !== lanEnabled || port !== data?.port),
    [data, enabled, lanEnabled, port],
  );

  const save = useMutation({
    mutationFn: () => api.configureWeb({ enabled, port, configureFirewall }),
    onSuccess: () => {
      toast.success("Web 远程管理配置已保存并生效");
      void queryClient.invalidateQueries({ queryKey: ["web-status"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const firewall = useMutation({
    mutationFn: (enable: boolean) => api.configureWebFirewall(enable),
    onSuccess: (_, enable) => {
      toast.success(enable ? "已放行 Web 端口防火墙规则" : "已移除 Web 端口防火墙规则");
      void queryClient.invalidateQueries({ queryKey: ["web-status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const copy = (value: string) => {
    navigator.clipboard
      .writeText(value)
      .then(() => toast.success("访问地址已复制"))
      .catch(() => toast.error("无法访问剪贴板"));
  };

  const valid = port >= 1 && port <= 65535;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="Web 远程管理"
        description="允许局域网设备通过浏览器访问管理页，并为管理端口放行防火墙。"
        actions={
          <Badge tone={lanEnabled ? "good" : "neutral"} dot>
            {lanEnabled ? "局域网可访问" : "仅本机访问"}
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {web.isLoading || !data ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={2} />
            <FieldGridSkeleton fields={2} />
          </div>
        ) : (
          <>
            <SwitchRow
              title="允许局域网访问"
              description="开启后监听 0.0.0.0，局域网内其他设备可打开管理页"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="grid gap-3 border-b border-border/60 py-2.5 sm:grid-cols-2">
              <Field label="管理端口" hint="1 – 65535，修改后监听会重启">
                <Input
                  type="number"
                  min={1}
                  max={65535}
                  value={port}
                  onChange={(event) => setPort(Number(event.target.value))}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                当前监听 {data.listenAddress || "—"} · 防火墙后端 {data.firewallBackend || "none"}
              </div>
            </div>

            <div className="mt-2 rounded-xl border border-border bg-surface-2 px-3 py-2.5">
              <div className="flex items-center justify-between gap-2">
                <span className="flex items-center gap-1.5 text-[11.5px] text-text-2">
                  <Wifi className="h-3.5 w-3.5 text-text-3" />
                  访问地址
                </span>
                <Badge tone={data.firewallAllowed ? "good" : "warn"}>
                  {data.firewallAllowed ? "防火墙已放行" : "防火墙未放行"}
                </Badge>
              </div>
              <div className="mt-2 space-y-1.5">
                {data.webUrls.map((url) => (
                  <div key={url} className="flex items-center gap-2">
                    <span className="mono min-w-0 flex-1 truncate text-[10.5px] text-text-2">
                      {url}
                    </span>
                    <button
                      type="button"
                      onClick={() => copy(url)}
                      className="shrink-0 rounded p-0.5 text-text-3 hover:text-text"
                      title="复制地址"
                      aria-label={`复制 ${url}`}
                    >
                      <Copy className="h-3 w-3" />
                    </button>
                    <a
                      href={url}
                      target="_blank"
                      rel="noreferrer"
                      className="shrink-0 rounded p-0.5 text-text-3 hover:text-text"
                      title="打开地址"
                      aria-label={`打开 ${url}`}
                    >
                      <ExternalLink className="h-3 w-3" />
                    </a>
                  </div>
                ))}
              </div>
            </div>

            <SwitchRow
              className="mt-1"
              title="保存时配置防火墙"
              description="启用远程访问时自动放行端口，关闭时清除规则"
              checked={configureFirewall}
              onCheckedChange={setConfigureFirewall}
            />

            {enabled ? (
              <p className="flex items-start gap-1.5 rounded-lg bg-warn-soft px-3 py-2 text-[11px] leading-5 text-warn">
                <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                管理页将对局域网开放，请使用强管理员密码，并仅在可信网络中启用。
              </p>
            ) : null}

            <div className="mt-auto flex flex-wrap items-center gap-2 pt-2">
              <Button
                size="sm"
                variant="secondary"
                loading={firewall.isPending}
                disabled={data.firewallBackend === "none"}
                onClick={() => firewall.mutate(!data.firewallAllowed)}
              >
                <ShieldCheck className="h-3.5 w-3.5" />
                {data.firewallAllowed ? "移除防火墙规则" : "放行防火墙"}
              </Button>
              <span className="text-[10px] text-text-3">
                修改端口后服务会重启监听，可能需要用新地址重新打开页面。
              </span>
            </div>
          </>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {dirty ? "存在未保存修改" : "配置已同步"}
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
