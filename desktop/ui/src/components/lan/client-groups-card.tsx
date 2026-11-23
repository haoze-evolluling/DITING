import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Save, Trash2, UsersRound } from "lucide-react";
import { toast } from "sonner";

import { useClientGroups } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import type { ClientGroup } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { EmptyState } from "../ui/empty";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";
import { ClientGroupDialog } from "./client-group-dialog";

const blockModeLabels: Record<string, string> = {
  null_ip: "空地址",
  nxdomain: "NXDOMAIN",
  refused: "REFUSED",
};

export function ClientGroupsCard() {
  const data = useClientGroups();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [groups, setGroups] = useState<ClientGroup[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ClientGroup | null>(null);
  const configKey = JSON.stringify(
    data.data ? { enabled: data.data.enabled, groups: data.data.groups } : null,
  );

  useEffect(() => {
    if (!data.data) return;
    setEnabled(data.data.enabled);
    setGroups(data.data.groups.map((group) => ({ ...group })));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!data.data) return false;
    return (
      enabled !== data.data.enabled ||
      JSON.stringify(groups) !== JSON.stringify(data.data.groups)
    );
  }, [data.data, enabled, groups]);

  const save = useMutation({
    mutationFn: () => api.configureClientGroups({ enabled, groups }),
    onSuccess: () => {
      toast.success("客户端分组已保存并生效");
      void queryClient.invalidateQueries({ queryKey: ["client-groups"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const submit = (group: ClientGroup) => {
    const next = group.id
      ? group
      : { ...group, id: `group-${Date.now().toString(36)}` };
    setGroups((current) => {
      const index = current.findIndex((item) => item.id === editing?.id);
      if (index < 0) return [...current, next];
      return current.map((item, position) => (position === index ? next : item));
    });
    setEditing(null);
    setDialogOpen(false);
  };

  const list = groups;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="客户端分组"
        description="按成员 IP 使用不同的订阅源、上游与拦截方式。"
        actions={
          <Button
            size="sm"
            variant="secondary"
            onClick={() => {
              setEditing(null);
              setDialogOpen(true);
            }}
          >
            <Plus className="h-3.5 w-3.5" />
            添加分组
          </Button>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {data.isLoading ? (
          <LoadingState label="正在加载客户端分组…" />
        ) : (
          <>
            <SwitchRow
              title="启用客户端分组"
              description="关闭后所有客户端使用全局策略"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="mt-2 min-h-0 flex-1">
              {list.length === 0 ? (
                <EmptyState
                  icon={UsersRound}
                  title="还没有客户端分组"
                  description="添加分组后，可为不同设备使用不同的规则与上游。"
                  action={
                    <Button
                      size="sm"
                      variant="primary"
                      onClick={() => {
                        setEditing(null);
                        setDialogOpen(true);
                      }}
                    >
                      <Plus className="h-3.5 w-3.5" />
                      添加分组
                    </Button>
                  }
                />
              ) : (
                <div className="divide-y divide-border/70">
                  {list.map((group) => (
                    <div key={group.id} className="flex items-start gap-3 py-2.5">
                      <span className="mt-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-surface-3 text-text-3">
                        <UsersRound className="h-3.5 w-3.5" />
                      </span>
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="truncate text-[12.5px] font-medium text-text">
                            {group.name}
                          </span>
                          <Badge tone={group.enabled ? "good" : "neutral"}>
                            {group.enabled ? "启用" : "停用"}
                          </Badge>
                          {group.allowlistOnly ? <Badge tone="warn">仅白名单</Badge> : null}
                          {group.blockMode ? (
                            <Badge tone="neutral">
                              {blockModeLabels[group.blockMode] ?? group.blockMode}
                            </Badge>
                          ) : null}
                        </div>
                        <div className="mono mt-1 truncate text-[10.5px] text-text-3">
                          {group.clients.join(", ") || "无成员"}
                        </div>
                        <div className="mt-1 flex flex-wrap gap-1 text-[10px] text-text-3">
                          <span>{group.clients.length} 个成员</span>
                          {group.ruleListIds && group.ruleListIds.length > 0 ? (
                            <span>· {group.ruleListIds.length} 个订阅源</span>
                          ) : null}
                          {group.upstreamIds && group.upstreamIds.length > 0 ? (
                            <span>· {group.upstreamIds.length} 个上游</span>
                          ) : null}
                        </div>
                      </div>
                      <div className="flex shrink-0 items-center gap-0.5">
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={`编辑 ${group.name}`}
                          onClick={() => {
                            setEditing(group);
                            setDialogOpen(true);
                          }}
                        >
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={`删除 ${group.name}`}
                          onClick={() =>
                            setGroups((current) =>
                              current.filter((item) => item.id !== group.id),
                            )
                          }
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
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
          disabled={!dirty}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          <Save className="h-3.5 w-3.5" />
          保存
        </Button>
      </CardFooter>

      <ClientGroupDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open);
          if (!open) setEditing(null);
        }}
        initial={editing}
        ruleLists={data.data?.ruleLists ?? []}
        upstreams={data.data?.upstreams ?? []}
        loading={false}
        onSubmit={submit}
      />
    </Card>
  );
}
