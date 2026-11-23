import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ShieldAlert } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { SwitchRowsSkeleton, TextareaSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

export function RebindCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [domains, setDomains] = useState("");
  const config = status.data?.rebind;
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setDomains(joinLines(config.allowedDomains));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const domainList = useMemo(() => parseLines(domains), [domains]);
  const dirty = useMemo(
    () =>
      Boolean(config) &&
      (enabled !== config?.enabled ||
        JSON.stringify(domainList) !== JSON.stringify(config?.allowedDomains ?? [])),
    [config, enabled, domainList],
  );

  const save = useMutation({
    mutationFn: () => api.configureRebind({ enabled, allowedDomains: domainList }),
    onSuccess: () => {
      toast.success("DNS Rebinding 防御配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="DNS Rebinding 防御"
        description="拒绝解析结果为内网地址的公网域名，防止绕过同源策略。"
        actions={<ShieldAlert className="h-4 w-4 text-text-3" />}
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
              title="启用重绑定保护"
              description="命中允许列表的域名不受限制"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <Field
              label="允许的域名 / 后缀"
              hint="每行一条。以 . 开头的条目按后缀匹配，例如 .lan。"
              className="mt-2"
            >
              <Textarea
                className="mono min-h-[120px] text-[11.5px]"
                value={domains}
                spellCheck={false}
                placeholder={"localhost\n.local\n.lan\n.home.arpa"}
                onChange={(event) => setDomains(event.target.value)}
              />
            </Field>
            <p className="text-[10.5px] leading-4 text-text-3">
              当前允许 {domainList.length} 条；关闭保护后所有内网地址应答都会被放行。
            </p>
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
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
