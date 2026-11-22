import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Save, UserCheck, UserX } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { Skeleton } from "../ui/skeleton";

export function AccessControlCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [allowed, setAllowed] = useState("");
  const [blocked, setBlocked] = useState("");
  const accessKey = JSON.stringify(status.data?.access ?? null);

  useEffect(() => {
    if (!status.data?.access) return;
    setAllowed(joinLines(status.data.access.allowedClients));
    setBlocked(joinLines(status.data.access.blockedClients));
    // 仅在服务端配置实际变化时重置草稿，避免状态轮询覆盖正在编辑的内容。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accessKey]);

  const config = status.data?.access;
  const allowedList = useMemo(() => parseLines(allowed), [allowed]);
  const blockedList = useMemo(() => parseLines(blocked), [blocked]);

  const dirty = useMemo(() => {
    if (!config) return false;
    return (
      JSON.stringify(allowedList) !== JSON.stringify(config.allowedClients) ||
      JSON.stringify(blockedList) !== JSON.stringify(config.blockedClients)
    );
  }, [config, allowedList, blockedList]);

  const save = useMutation({
    mutationFn: () => api.configureAccess(allowedList, blockedList),
    onSuccess: () => {
      toast.success("客户端访问控制已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="客户端访问控制"
        description="按 IP 或 CIDR 网段限制哪些终端可以使用本机解析。"
      />
      <CardContent className="flex flex-1 flex-col gap-3 pt-2">
        {status.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <>
            <Field
              label="允许访问（白名单）"
              hint="每行一个 IP 或网段。填写后仅列表内客户端可解析，留空表示允许全部。"
            >
              <Textarea
                className="mono min-h-[92px] text-[11.5px]"
                value={allowed}
                spellCheck={false}
                placeholder={"192.168.1.0/24\n10.0.0.8"}
                onChange={(event) => setAllowed(event.target.value)}
              />
            </Field>
            <Field
              label="阻断访问（黑名单）"
              hint="每行一个 IP 或网段。黑名单优先于白名单，被命中的客户端直接拒绝。"
            >
              <Textarea
                className="mono min-h-[92px] text-[11.5px]"
                value={blocked}
                spellCheck={false}
                placeholder={"203.0.113.5\n198.51.100.0/24"}
                onChange={(event) => setBlocked(event.target.value)}
              />
            </Field>
            <div className="flex flex-wrap gap-2">
              <span className="inline-flex items-center gap-1.5 rounded-lg bg-surface-2 px-2.5 py-1 text-[10.5px] text-text-3">
                <UserCheck className="h-3 w-3" />
                白名单 {allowedList.length} 条
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-lg bg-surface-2 px-2.5 py-1 text-[10.5px] text-text-3">
                <UserX className="h-3 w-3" />
                黑名单 {blockedList.length} 条
              </span>
              <span className="rounded-lg bg-warn-soft px-2.5 py-1 text-[10.5px] text-warn">
                启用白名单时请包含 127.0.0.1，否则本机系统解析会被拒绝
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
