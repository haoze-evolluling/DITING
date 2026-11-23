import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Route, Save, ShieldAlert } from "lucide-react";
import { toast } from "sonner";

import { useEncryptedStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseList } from "../../lib/strings";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { SwitchRowsSkeleton, TextareaSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

function isUnrestricted(entries: string[]): boolean {
  return entries.some((entry) => {
    const value = entry.trim();
    return value === "0.0.0.0/0" || value === "::/0";
  });
}

export function EncryptedAclCard() {
  const status = useEncryptedStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [sources, setSources] = useState("");
  const [header, setHeader] = useState("");
  const [confirm, setConfirm] = useState(false);
  const aclKey = status.data
    ? JSON.stringify({
        proxy: status.data.config.reverseProxy,
        unrestricted: status.data.unrestrictedTrust,
      })
    : null;

  useEffect(() => {
    const proxy = status.data?.config.reverseProxy;
    if (!proxy) return;
    setEnabled(proxy.enabled);
    setSources(joinLines(proxy.trustedSources));
    setHeader(proxy.clientIpHeader);
    setConfirm(Boolean(status.data?.unrestrictedTrust));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aclKey]);

  const sourceList = useMemo(() => parseList(sources), [sources]);
  const unrestricted = isUnrestricted(sourceList);

  const dirty = useMemo(() => {
    const proxy = status.data?.config.reverseProxy;
    if (!proxy) return false;
    return (
      enabled !== proxy.enabled ||
      header !== proxy.clientIpHeader ||
      JSON.stringify(sourceList) !== JSON.stringify(proxy.trustedSources)
    );
  }, [status.data, enabled, header, sourceList]);

  const save = useMutation({
    mutationFn: () =>
      api.configureEncryptedAcl({
        enabled,
        trustedSources: sourceList,
        clientIpHeader: header,
        confirmUnrestricted: confirm,
      }),
    onSuccess: () => {
      toast.success("反向代理可信来源已更新");
      void queryClient.invalidateQueries({ queryKey: ["encrypted-status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const blocked = unrestricted && !confirm;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="反向代理来源"
        description="仅当请求来自可信代理时，才采信客户端 IP 请求头。"
        actions={<Route className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={1} />
            <TextareaSkeleton />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用反向代理支持"
              description="关闭后忽略所有代理请求头，直接使用连接来源"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <Field
              label="可信来源"
              hint="每行一个 IP 或 CIDR。只有来自这些地址的请求才会读取下方请求头。"
              className="mt-3"
            >
              <Textarea
                className="mono min-h-[92px] text-[11.5px]"
                value={sources}
                spellCheck={false}
                placeholder={"127.0.0.1\n192.168.1.0/24"}
                onChange={(event) => setSources(event.target.value)}
              />
            </Field>
            <Field label="客户端 IP 请求头" hint="例如 X-Forwarded-For 或 X-Real-IP">
              <Input
                className="mono"
                value={header}
                placeholder="X-Forwarded-For"
                onChange={(event) => setHeader(event.target.value)}
              />
            </Field>

            {unrestricted ? (
              <div className="mt-2 rounded-xl border border-danger/25 bg-danger-soft px-3.5 py-3">
                <div className="flex items-start gap-2 text-[11.5px] leading-5 text-danger">
                  <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <div>
                    <p className="font-medium">可信来源包含全部网段</p>
                    <p className="mt-0.5 opacity-90">
                      0.0.0.0/0 或 ::/0 会让任何直连方伪造客户端来源，访问控制与速率限制将同时失效。
                    </p>
                  </div>
                </div>
                <label className="mt-2 flex items-center gap-2 text-[11px] text-danger">
                  <input
                    type="checkbox"
                    checked={confirm}
                    onChange={(event) => setConfirm(event.target.checked)}
                  />
                  我确认接受该风险
                </label>
              </div>
            ) : null}
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
          disabled={!dirty || blocked}
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
