import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Network } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { FieldGridSkeleton, SwitchRowsSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

export function Dns64Card() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [prefixes, setPrefixes] = useState("");
  const config = status.data?.dns64;
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setPrefixes(joinLines(config.prefixes));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const prefixList = useMemo(() => parseLines(prefixes), [prefixes]);
  const dirty = useMemo(
    () =>
      Boolean(config) &&
      (enabled !== config?.enabled ||
        JSON.stringify(prefixList) !== JSON.stringify(config?.prefixes ?? [])),
    [config, enabled, prefixList],
  );

  const save = useMutation({
    mutationFn: () => api.configureDns64({ enabled, prefixes: prefixList }),
    onSuccess: () => {
      toast.success("DNS64 过渡合成配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="DNS64 过渡合成"
        description="在 IPv6-only 网络中，用 A 记录合成 AAAA 应答。"
        actions={<Network className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={1} />
            <FieldGridSkeleton fields={2} />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用 DNS64"
              description="仅当查询 AAAA 无结果且存在 A 记录时合成"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <Field
              label="合成前缀"
              hint="每行一个 IPv6 前缀，默认使用 64:ff9b::/96。"
              className="mt-2"
            >
              <Textarea
                className="mono min-h-[96px] text-[11.5px]"
                value={prefixes}
                spellCheck={false}
                placeholder="64:ff9b::/96"
                onChange={(event) => setPrefixes(event.target.value)}
              />
            </Field>
            <p className="text-[10.5px] leading-4 text-text-3">
              需要网络侧提供对应的 NAT64 网关，否则合成地址可能无法连通。
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
          disabled={!dirty || (enabled && prefixList.length === 0)}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
