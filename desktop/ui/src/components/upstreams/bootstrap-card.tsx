import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import type { BootstrapConfig, BootstrapServer } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Input } from "../ui/input";
import { Skeleton } from "../ui/skeleton";
import { SwitchRow } from "../ui/switch-row";

let counter = 0;

function newServer(): BootstrapServer {
  counter += 1;
  return {
    id: `bs-${Date.now()}-${counter}`,
    name: "自定义 Bootstrap",
    address: "223.5.5.5:53",
    weight: 1,
  };
}

export function BootstrapCard({
  config,
  loading,
}: {
  config?: BootstrapConfig;
  loading: boolean;
}) {
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [servers, setServers] = useState<BootstrapServer[]>([]);
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setServers(config.servers.map((server) => ({ ...server })));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const save = useMutation({
    mutationFn: () => api.configureBootstrap({ enabled, servers }),
    onSuccess: () => {
      toast.success("Bootstrap DNS 已更新");
      void queryClient.invalidateQueries({ queryKey: ["upstream-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (index: number, patch: Partial<BootstrapServer>) =>
    setServers((current) =>
      current.map((server, position) => (position === index ? { ...server, ...patch } : server)),
    );

  const invalid = servers.some((server) => !server.name.trim() || !server.address.trim());

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="Bootstrap DNS"
        description="用于首次解析加密上游域名，避免解析死锁。"
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {loading ? (
          <div className="space-y-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-11 w-full" />
            <Skeleton className="h-11 w-full" />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用 Bootstrap"
              description="加密上游首次连接时使用下列明文 DNS 解析其域名"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="mt-2 space-y-2">
              {servers.map((server, index) => (
                <div
                  key={server.id}
                  className="grid grid-cols-[1fr_1fr_auto] items-center gap-2 rounded-xl border border-border bg-surface-2 p-2.5"
                >
                  <Input
                    value={server.name}
                    placeholder="名称"
                    aria-label="Bootstrap 名称"
                    onChange={(event) => update(index, { name: event.target.value })}
                  />
                  <Input
                    value={server.address}
                    placeholder="223.5.5.5:53"
                    aria-label="Bootstrap 地址"
                    className="mono"
                    onChange={(event) => update(index, { address: event.target.value })}
                  />
                  <Button
                    size="icon"
                    variant="ghost"
                    aria-label="删除 Bootstrap 服务器"
                    onClick={() =>
                      setServers((current) => current.filter((_, position) => position !== index))
                    }
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ))}
              <Button size="sm" variant="secondary" onClick={() => setServers((c) => [...c, newServer()])}>
                <Plus className="h-3.5 w-3.5" />
                添加服务器
              </Button>
            </div>
            {enabled && servers.length === 0 ? (
              <p className="mt-2 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                启用 Bootstrap 时至少需要一台服务器。
              </p>
            ) : null}
          </>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">保存后立即用于后续加密连接</span>
        <Button
          size="sm"
          variant="primary"
          loading={save.isPending}
          disabled={loading || invalid || (enabled && servers.length === 0)}
          onClick={() => save.mutate()}
        >
          <Save className="h-3.5 w-3.5" />
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
