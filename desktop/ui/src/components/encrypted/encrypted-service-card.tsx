import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Download, LockKeyhole, Radio, Save } from "lucide-react";
import { toast } from "sonner";

import { useEncryptedStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import type { EncryptedDNSConfig } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

function Subset(config: EncryptedDNSConfig) {
  return {
    enabled: config.enabled,
    dotEnabled: config.dotEnabled,
    dohEnabled: config.dohEnabled,
    ddrEnabled: config.ddrEnabled,
    listenAddress: config.listenAddress,
    dotPort: config.dotPort,
    dohPort: config.dohPort,
    dohPath: config.dohPath,
    serverName: config.serverName,
  };
}

export function EncryptedServiceCard() {
  const status = useEncryptedStatus();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<EncryptedDNSConfig | null>(null);
  const configKey = status.data ? JSON.stringify(status.data.config) : null;

  useEffect(() => {
    if (status.data) setDraft({ ...status.data.config });
    // 仅在服务端配置实际变化时重置草稿，避免状态轮询覆盖正在编辑的内容。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!status.data || !draft) return false;
    return JSON.stringify(Subset(draft)) !== JSON.stringify(Subset(status.data.config));
  }, [status.data, draft]);

  const save = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("配置尚未加载");
      return api.configureEncryptedDns(Subset(draft));
    },
    onSuccess: () => {
      toast.success("加密 DNS 配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["encrypted-status"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<EncryptedDNSConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const download = useMutation({
    mutationFn: (protocol: "https" | "tls") => api.downloadMobileConfig(protocol),
    onSuccess: () => toast.success("描述文件已开始下载"),
    onError: (error) => toast.error(describeError(error)),
  });

  if (status.isLoading || !draft) {
    return (
      <Card className="flex flex-col">
        <CardHeader
          title="加密 DNS 服务"
          description="面向局域网提供 DoT 与 DoH，证书由本机签发或导入。"
          actions={<LockKeyhole className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <LoadingState label="正在加载加密 DNS 配置…" />
        </CardContent>
      </Card>
    );
  }

  const data = status.data;
  const validPorts =
    (draft.dotPort === 0 || (draft.dotPort >= 1 && draft.dotPort <= 65535)) &&
    (draft.dohPort === 0 || (draft.dohPort >= 1 && draft.dohPort <= 65535));
  const saveDisabled = !dirty || !validPorts;

  return (
    <>
      <Card className="flex flex-col">
        <CardHeader
          title="加密 DNS 服务"
          description="面向局域网提供 DoT 与 DoH，证书由本机签发或导入。"
          actions={<LockKeyhole className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <SwitchRow
            title="启用加密 DNS"
            description="总开关，关闭后 DoT 与 DoH 均不监听"
            checked={draft.enabled}
            onCheckedChange={(enabled) => update({ enabled })}
          />
          <div className="grid gap-3 pt-3 xl:grid-cols-2">
            <div className="rounded-xl border border-border bg-surface-2 p-3">
              <SwitchRow
                title="DoT（DNS over TLS）"
                checked={draft.dotEnabled}
                onCheckedChange={(value) => update({ dotEnabled: value })}
                disabled={!draft.enabled}
                className="border-b-0 py-0"
              />
              <Field label="端口" className="mt-2">
                <Input
                  type="number"
                  min={1}
                  max={65535}
                  value={draft.dotPort}
                  disabled={!draft.enabled || !draft.dotEnabled}
                  onChange={(event) => update({ dotPort: Number(event.target.value) })}
                />
              </Field>
              <div className="mono mt-2 truncate text-[10.5px] text-text-3">
                {data?.dotListen || "尚未监听"}
              </div>
            </div>
            <div className="rounded-xl border border-border bg-surface-2 p-3">
              <SwitchRow
                title="DoH（DNS over HTTPS）"
                checked={draft.dohEnabled}
                onCheckedChange={(value) => update({ dohEnabled: value })}
                disabled={!draft.enabled}
                className="border-b-0 py-0"
              />
              <div className="mt-2 grid grid-cols-[1fr_1.4fr] gap-2">
                <Field label="端口">
                  <Input
                    type="number"
                    min={1}
                    max={65535}
                    value={draft.dohPort}
                    disabled={!draft.enabled || !draft.dohEnabled}
                    onChange={(event) => update({ dohPort: Number(event.target.value) })}
                  />
                </Field>
                <Field label="路径">
                  <Input
                    className="mono"
                    value={draft.dohPath}
                    disabled={!draft.enabled || !draft.dohEnabled}
                    onChange={(event) => update({ dohPath: event.target.value })}
                  />
                </Field>
              </div>
              <div className="mono mt-2 space-y-0.5 text-[10.5px] text-text-3">
                {data?.dohUrls?.length ? (
                  data.dohUrls.slice(0, 3).map((url) => (
                    <div key={url} className="truncate" title={url}>
                      {url}
                    </div>
                  ))
                ) : (
                  <div>{data?.dohListen || "尚未监听"}</div>
                )}
              </div>
            </div>
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <Badge tone={draft.dotEnabled && draft.enabled ? "good" : "neutral"} dot>
              DoT {draft.dotEnabled && draft.enabled ? "已启用" : "未启用"}
            </Badge>
            <Badge tone={draft.dohEnabled && draft.enabled ? "good" : "neutral"} dot>
              DoH {draft.dohEnabled && draft.enabled ? "已启用" : "未启用"}
            </Badge>
            {!validPorts ? (
              <span className="text-[10.5px] text-danger">端口需在 1 – 65535 之间</span>
            ) : null}
          </div>
        </CardContent>
        <CardFooter>
          <div className="flex flex-wrap items-center gap-1.5">
            <Button
              size="sm"
              variant="ghost"
              loading={download.isPending && download.variables === "tls"}
              disabled={!data?.config.dotEnabled || !data.config.enabled}
              onClick={() => download.mutate("tls")}
            >
              <Download className="h-3.5 w-3.5" />
              DoT 描述文件
            </Button>
            <Button
              size="sm"
              variant="ghost"
              loading={download.isPending && download.variables === "https"}
              disabled={!data?.config.dohEnabled || !data.config.enabled}
              onClick={() => download.mutate("https")}
            >
              <Download className="h-3.5 w-3.5" />
              DoH 描述文件
            </Button>
          </div>
          <Button
            size="sm"
            variant="primary"
            disabled={saveDisabled}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            <Save className="h-3.5 w-3.5" />
            保存
          </Button>
        </CardFooter>
      </Card>

      <Card className="flex flex-col">
        <CardHeader
          title="监听与发现"
          description="监听网卡、服务器名与 DDR 声明。"
          actions={<Radio className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="监听地址" hint="留空表示监听所有网卡">
              <Input
                className="mono"
                value={draft.listenAddress}
                placeholder="0.0.0.0"
                onChange={(event) => update({ listenAddress: event.target.value })}
              />
            </Field>
            <Field label="服务器名" hint="写入证书 SAN 与 DoH 地址">
              <Input
                className="mono"
                value={draft.serverName}
                placeholder="dns.lan"
                onChange={(event) => update({ serverName: event.target.value })}
              />
            </Field>
          </div>

          <SwitchRow
            className="mt-1"
            title="DDR（Discovery of Designated Resolvers）"
            description="向客户端声明本服务器的加密解析能力"
            checked={draft.ddrEnabled}
            onCheckedChange={(value) => update({ ddrEnabled: value })}
            disabled={!draft.enabled}
          />
        </CardContent>
        <CardFooter>
          <span className="text-[10.5px] text-text-3">
            {dirty ? "存在未保存修改" : "配置已同步"}
          </span>
          <Button
            size="sm"
            variant="primary"
            disabled={saveDisabled}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            <Save className="h-3.5 w-3.5" />
            保存
          </Button>
        </CardFooter>
      </Card>
    </>
  );
}
