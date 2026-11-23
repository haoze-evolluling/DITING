import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ListPlus, Pencil, RefreshCw, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { useFilterLists } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatRelative } from "../../lib/format";
import type { FilterList } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { EmptyState } from "../ui/empty";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { Switch } from "../ui/switch";
import { SwitchRow } from "../ui/switch-row";

interface ListDraft {
  name: string;
  url: string;
  enabled: boolean;
}

function ListDialog({
  open,
  onOpenChange,
  initial,
  onSubmit,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: FilterList | null;
  onSubmit: (draft: ListDraft) => void;
}) {
  const [draft, setDraft] = useState<ListDraft>({ name: "", url: "", enabled: true });

  useEffect(() => {
    if (!open) return;
    setDraft(
      initial
        ? { name: initial.name, url: initial.url, enabled: initial.enabled }
        : { name: "", url: "", enabled: true },
    );
  }, [open, initial]);

  const valid = draft.url.trim().length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(520px,calc(100vw-40px))]">
        <DialogHeader
          title={initial ? "编辑订阅源" : "添加订阅源"}
          description="支持 AdGuard / Adblock 语法、hosts 与 dnsmasq 行格式。"
        />
        <DialogBody className="space-y-3.5">
          <Field label="名称" hint="留空时使用订阅源 ID 或 URL">
            <Input
              value={draft.name}
              placeholder="AdGuard DNS Filter"
              onChange={(event) => setDraft((c) => ({ ...c, name: event.target.value }))}
            />
          </Field>
          <Field label="订阅地址" hint="必须是可以直接下载的纯文本规则地址">
            <Input
              value={draft.url}
              placeholder="https://example.com/filter.txt"
              className="mono"
              onChange={(event) => setDraft((c) => ({ ...c, url: event.target.value }))}
            />
          </Field>
          <SwitchRow
            title="启用该订阅"
            checked={draft.enabled}
            onCheckedChange={(enabled) => setDraft((c) => ({ ...c, enabled }))}
          />
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button
            variant="primary"
            disabled={!valid}
            onClick={() => {
              onSubmit({ ...draft, name: draft.name.trim(), url: draft.url.trim() });
              onOpenChange(false);
            }}
          >
            保存
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function FilterListsCard() {
  const lists = useFilterLists();
  const queryClient = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<FilterList | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<FilterList | null>(null);

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["filter-lists"] });
    void queryClient.invalidateQueries({ queryKey: ["filter-config"] });
    void queryClient.invalidateQueries({ queryKey: ["status"] });
  };

  const add = useMutation({
    mutationFn: (draft: ListDraft) => api.addFilterList(draft),
    onSuccess: () => {
      toast.success("订阅源已添加并完成索引");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = useMutation({
    mutationFn: (list: FilterList) => api.updateFilterList(list),
    onSuccess: () => {
      toast.success("订阅源已更新");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.deleteFilterList(id),
    onSuccess: () => {
      toast.success("订阅源已删除");
      setDeleteTarget(null);
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const refresh = useMutation({
    mutationFn: (id?: string) => api.refreshFilterLists(id),
    onSuccess: (_, id) => {
      toast.success(id ? "订阅源已刷新" : "全部订阅源已刷新");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const items = lists.data?.lists ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="规则订阅"
        description="在线规则源会被拉取、解析并建立索引。"
        actions={
          <>
            <Button
              size="sm"
              variant="ghost"
              loading={refresh.isPending && refresh.variables === undefined}
              onClick={() => refresh.mutate(undefined)}
              disabled={items.length === 0}
            >
              <RefreshCw className="h-3.5 w-3.5" />
              全部刷新
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                setEditing(null);
                setDialogOpen(true);
              }}
            >
              <ListPlus className="h-3.5 w-3.5" />
              添加
            </Button>
          </>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {lists.isLoading ? (
          <LoadingState label="正在加载订阅源…" className="min-h-[140px]" />
        ) : items.length === 0 ? (
          <EmptyState
            icon={ListPlus}
            title="还没有订阅源"
            description="添加在线规则源，或使用下方自定义规则。"
          />
        ) : (
          <div className="divide-y divide-border/70">
            {items.map((list) => (
              <div key={list.id} className="flex items-start gap-3 py-3">
                <Switch
                  checked={list.enabled}
                  onCheckedChange={(enabled) => update.mutate({ ...list, enabled })}
                  disabled={update.isPending}
                  label={`启用 ${list.name}`}
                />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="truncate text-[12.5px] font-medium text-text">{list.name}</span>
                    <Badge tone={list.enabled ? "good" : "neutral"}>
                      {list.enabled ? "启用" : "停用"}
                    </Badge>
                    {list.lastStatus && list.lastStatus !== "ok" ? (
                      <Badge tone={list.lastStatus === "error" ? "danger" : "warn"}>
                        {list.lastStatus}
                      </Badge>
                    ) : null}
                  </div>
                  <div className="mono mt-1 truncate text-[10.5px] text-text-3">{list.url}</div>
                  <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 text-[10.5px] text-text-3">
                    <span className="num">{list.rulesCount.toLocaleString("zh-CN")} 条规则</span>
                    <span>
                      更新于 {list.lastUpdated ? formatRelative(list.lastUpdated) : "从未更新"}
                    </span>
                    {list.lastError ? <span className="text-danger">{list.lastError}</span> : null}
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-0.5">
                  <Button
                    size="icon"
                    variant="ghost"
                    aria-label={`刷新 ${list.name}`}
                    loading={refresh.isPending && refresh.variables === list.id}
                    onClick={() => refresh.mutate(list.id)}
                  >
                    <RefreshCw className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    aria-label={`编辑 ${list.name}`}
                    onClick={() => {
                      setEditing(list);
                      setDialogOpen(true);
                    }}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    aria-label={`删除 ${list.name}`}
                    onClick={() => setDeleteTarget(list)}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">共 {items.length} 个订阅源</span>
        <span className="text-[10.5px] text-text-3">
          {items.filter((list) => list.enabled).length} 个启用
        </span>
      </CardFooter>

      <ListDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        initial={editing}
        onSubmit={(draft) => {
          if (editing) update.mutate({ ...editing, ...draft });
          else add.mutate(draft);
        }}
      />

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="删除订阅源"
        description={`确定要删除「${deleteTarget?.name ?? ""}」吗？其规则会立即从索引中移除。`}
        confirmLabel="删除"
        loading={remove.isPending}
        onConfirm={() => deleteTarget && remove.mutate(deleteTarget.id)}
      />
    </Card>
  );
}
