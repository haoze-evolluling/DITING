import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Copy, Database, Save, SlidersHorizontal } from "lucide-react";
import { toast } from "sonner";

import { useMeta, useQueryLogConfig } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { copyText } from "../../lib/clipboard";
import { formatNumber } from "../../lib/format";
import type { QueryLogConfig } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

function SaveFooter({
  dirty,
  valid,
  pending,
  onSave,
}: {
  dirty: boolean;
  valid: boolean;
  pending: boolean;
  onSave: () => void;
}) {
  return (
    <CardFooter>
      <span className="text-[10.5px] text-text-3">
        {dirty ? "存在未保存修改" : "配置已同步"}
      </span>
      <Button
        size="sm"
        variant="primary"
        disabled={!dirty || !valid}
        loading={pending}
        onClick={onSave}
      >
        <Save className="h-3.5 w-3.5" />
        保存
      </Button>
    </CardFooter>
  );
}

export function QueryLogCard() {
  const config = useQueryLogConfig();
  const meta = useMeta();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<QueryLogConfig | null>(null);

  useEffect(() => {
    if (config.data) setDraft(config.data);
  }, [config.data]);

  const save = useMutation({
    mutationFn: (value: QueryLogConfig) =>
      api.updateQueryConfig({
        enabled: value.enabled,
        fileEnabled: value.fileEnabled,
        logClients: value.logClients,
        maxEntries: value.maxEntries,
        retentionDays: value.retentionDays,
      }),
    onSuccess: () => {
      toast.success("查询日志配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["query-config"] });
      void queryClient.invalidateQueries({ queryKey: ["query-stats"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<QueryLogConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  if (config.isLoading || !draft) {
    return (
      <Card className="flex flex-col">
        <CardHeader
          title="查询日志"
          description="控制内存日志容量、持久化与保留周期。"
          actions={<Database className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <LoadingState label="正在加载日志配置…" />
        </CardContent>
      </Card>
    );
  }

  const valid =
    draft.maxEntries >= 100 &&
    draft.maxEntries <= 200_000 &&
    draft.retentionDays >= 1 &&
    draft.retentionDays <= 365;

  return (
    <>
      <Card className="flex flex-col">
        <CardHeader
          title="日志记录"
          description="控制是否记录查询、是否持久化以及是否记录客户端地址。"
          actions={<Database className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <SwitchRow
            title="记录查询日志"
            description="关闭后不再记录新的解析请求"
            checked={draft.enabled}
            onCheckedChange={(enabled) => update({ enabled })}
          />
          <SwitchRow
            title="持久化查询日志"
            description="写入 SQLite 数据库，服务重启后可检索"
            checked={draft.fileEnabled}
            onCheckedChange={(fileEnabled) => update({ fileEnabled })}
          />
          <SwitchRow
            title="记录客户端地址"
            description="用于客户端排名与访问排查"
            checked={draft.logClients}
            onCheckedChange={(logClients) => update({ logClients })}
          />
        </CardContent>
        <SaveFooter
          dirty={Boolean(config.data && JSON.stringify(draft) !== JSON.stringify(config.data))}
          valid={valid}
          pending={save.isPending}
          onSave={() => save.mutate(draft)}
        />
      </Card>

      <Card className="flex flex-col">
        <CardHeader
          title="容量与位置"
          description="内存日志上限、保留周期与数据库位置。"
          actions={<SlidersHorizontal className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex flex-1 flex-col pt-1">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className="text-[12px] text-text">内存最大条目</span>
              <Input
                className="mt-1.5"
                type="number"
                min={100}
                max={200000}
                value={draft.maxEntries}
                onChange={(event) => update({ maxEntries: Number(event.target.value) })}
              />
              <span className="mt-1 block text-[10.5px] text-text-3">
                100 – 200,000 条，当前 {formatNumber(draft.maxEntries)}
              </span>
            </label>
            <label className="block">
              <span className="text-[12px] text-text">保留天数</span>
              <Input
                className="mt-1.5"
                type="number"
                min={1}
                max={365}
                value={draft.retentionDays}
                onChange={(event) => update({ retentionDays: Number(event.target.value) })}
              />
              <span className="mt-1 block text-[10.5px] text-text-3">
                1 – 365 天，当前 {draft.retentionDays} 天
              </span>
            </label>
          </div>

          <div className="mt-3">
            <div className="text-[11px] text-text-3">数据库位置</div>
            <div className="mt-1.5 flex items-center gap-2 rounded-lg bg-surface-2 px-2.5 py-1.5">
              <span
                className="mono min-w-0 flex-1 truncate text-[10.5px] text-text-2"
                title={meta.data?.databasePath ?? undefined}
              >
                {meta.data?.databasePath ?? "—"}
              </span>
              <button
                type="button"
                disabled={!meta.data?.databasePath}
                onClick={() => {
                  if (meta.data?.databasePath) copyText(meta.data.databasePath, "数据库位置");
                }}
                className="shrink-0 rounded p-0.5 text-text-3 hover:text-text disabled:cursor-not-allowed disabled:opacity-40"
                title="复制数据库位置"
                aria-label="复制数据库位置"
              >
                <Copy className="h-3 w-3" />
              </button>
            </div>
          </div>

          {!valid ? (
            <p className="mt-3 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
              容量或保留天数超出允许范围，修正后才能保存。
            </p>
          ) : null}
        </CardContent>
        <SaveFooter
          dirty={Boolean(config.data && JSON.stringify(draft) !== JSON.stringify(config.data))}
          valid={valid}
          pending={save.isPending}
          onSave={() => save.mutate(draft)}
        />
      </Card>
    </>
  );
}
