import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { FileText } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

export function HostsCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [useSystemHost, setUseSystemHost] = useState(true);
  const [files, setFiles] = useState("");
  const [ttl, setTtl] = useState(60);
  const config = status.data?.hosts;
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setUseSystemHost(config.useSystemHost);
    setFiles(joinLines(config.customFiles));
    setTtl(config.ttl);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const fileList = useMemo(() => parseLines(files), [files]);
  const dirty = useMemo(
    () =>
      Boolean(config) &&
      (enabled !== config?.enabled ||
        useSystemHost !== config?.useSystemHost ||
        ttl !== config?.ttl ||
        JSON.stringify(fileList) !== JSON.stringify(config?.customFiles ?? [])),
    [config, enabled, useSystemHost, ttl, fileList],
  );

  const save = useMutation({
    mutationFn: () =>
      api.configureHosts({
        enabled,
        useSystemHost,
        customFiles: fileList,
        ttl,
      }),
    onSuccess: () => {
      toast.success("Hosts 解析器配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="Hosts 解析"
        description="复用系统 hosts 与自定义 hosts 文件，优先于上游解析。"
        actions={<FileText className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading ? (
          <LoadingState label="正在加载 Hosts 配置…" />
        ) : (
          <>
            <SwitchRow
              title="启用 Hosts 解析"
              description="关闭后忽略所有 hosts 条目"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <SwitchRow
              title="读取系统 hosts"
              description="加载操作系统默认 hosts 文件"
              checked={useSystemHost}
              onCheckedChange={setUseSystemHost}
            />
            <div className="grid gap-3 border-b border-border/60 py-2.5 sm:grid-cols-2">
              <Field label="记录 TTL（秒）">
                <Input
                  type="number"
                  min={1}
                  max={86400}
                  value={ttl}
                  onChange={(event) => setTtl(Number(event.target.value))}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                hosts 命中会直接生成应答，不再经过缓存与上游。
              </div>
            </div>
            <Field
              label="自定义 hosts 文件"
              hint="每行一个绝对路径；文件格式与系统 hosts 相同。"
              className="mt-2"
            >
              <Textarea
                className="mono min-h-[92px] text-[11.5px]"
                value={files}
                spellCheck={false}
                placeholder={"C:\\diting\\hosts.txt\n/etc/diting/hosts"}
                onChange={(event) => setFiles(event.target.value)}
              />
            </Field>
            {!enabled ? (
              <p className="rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] text-text-3">
                Hosts 解析已关闭，下列路径不会生效。
              </p>
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
          disabled={!dirty || !Number.isFinite(ttl) || ttl <= 0}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
