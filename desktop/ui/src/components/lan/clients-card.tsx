import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Pencil, Users } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber, formatRelative } from "../../lib/format";
import type { ClientSummary } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
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
import { Skeleton } from "../ui/skeleton";

export function ClientsCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<ClientSummary | null>(null);
  const [name, setName] = useState("");

  useEffect(() => {
    if (editing) setName("");
  }, [editing]);

  const save = useMutation({
    mutationFn: (input: { ip: string; name: string }) =>
      api.setClientAlias(input.ip, input.name),
    onSuccess: () => {
      toast.success("客户端别名已更新");
      setEditing(null);
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const clients = status.data?.clients ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="最近客户端"
        description="按查询量排序的局域网客户端，可设置别名便于识别。"
        actions={<Users className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {status.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : clients.length === 0 ? (
          <EmptyState
            icon={Users}
            title="暂无客户端记录"
            description="开启局域网 DNS 后，来自其他终端的查询会显示在这里。"
          />
        ) : (
          <div className="divide-y divide-border/70">
            {clients.slice(0, 12).map((client) => (
              <div key={client.ip} className="flex items-center gap-3 py-2.5">
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[12px] font-medium text-text">{client.name}</div>
                  <div className="mono mt-0.5 text-[10.5px] text-text-3">{client.ip}</div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="num text-[12px] text-text">{formatNumber(client.queryCount)} 次</div>
                  <div className="mt-0.5 text-[10px] text-text-3">
                    {client.lastSeen ? formatRelative(client.lastSeen * 1000) : "—"}
                  </div>
                </div>
                <Button
                  size="icon"
                  variant="ghost"
                  aria-label={`设置 ${client.ip} 的别名`}
                  onClick={() => setEditing(client)}
                >
                  <Pencil className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={Boolean(editing)} onOpenChange={(open) => !open && setEditing(null)}>
        <DialogContent className="w-[min(420px,calc(100vw-40px))]">
          <DialogHeader
            title="客户端别名"
            description={editing ? `为 ${editing.ip} 设置便于识别的名称` : undefined}
          />
          <DialogBody>
            <Field label="别名" hint="留空可清除别名，恢复为反向解析或 IP 显示。">
              <Input
                value={name}
                placeholder={editing?.name && editing.name !== editing.ip ? editing.name : "例如：客厅电视"}
                onChange={(event) => setName(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && editing) {
                    save.mutate({ ip: editing.ip, name: name.trim() });
                  }
                }}
              />
            </Field>
          </DialogBody>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setEditing(null)}>
              取消
            </Button>
            <Button
              variant="primary"
              loading={save.isPending}
              onClick={() => editing && save.mutate({ ip: editing.ip, name: name.trim() })}
            >
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
