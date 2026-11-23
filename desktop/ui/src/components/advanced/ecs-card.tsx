import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Globe2 } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

export function EcsCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [stripECS, setStripECS] = useState(true);
  const [customSubnet, setCustomSubnet] = useState("");
  const config = status.data?.ecs;
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setStripECS(config.stripECS);
    setCustomSubnet(config.customSubnet);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(
    () =>
      Boolean(config) &&
      (enabled !== config?.enabled ||
        stripECS !== config?.stripECS ||
        customSubnet !== config?.customSubnet),
    [config, enabled, stripECS, customSubnet],
  );

  const save = useMutation({
    mutationFn: () => api.configureEcs({ enabled, stripECS, customSubnet: customSubnet.trim() }),
    onSuccess: () => {
      toast.success("EDNS Client Subnet 配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="EDNS Client Subnet"
        description="控制是否向上游暴露客户端子网，或统一使用指定网段。"
        actions={<Globe2 className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading ? (
          <LoadingState label="正在加载 ECS 配置…" />
        ) : (
          <>
            <SwitchRow
              title="启用 ECS"
              description="关闭后不向上游发送客户端子网信息"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <SwitchRow
              title="剥离客户端 ECS"
              description="移除客户端携带的子网选项"
              checked={stripECS}
              onCheckedChange={setStripECS}
              disabled={!enabled}
            />
            <Field
              label="自定义子网"
              hint="留空表示使用上游默认策略；填写 CIDR 可强制统一出口定位。"
              className="mt-2"
            >
              <Input
                className="mono"
                value={customSubnet}
                placeholder="例如 203.0.113.0/24"
                disabled={!enabled}
                onChange={(event) => setCustomSubnet(event.target.value)}
              />
            </Field>
            <p className="text-[10.5px] leading-4 text-text-3">
              关闭 ECS 或剥离子网可以提升隐私，但可能降低 CDN 就近调度的准确度。
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
