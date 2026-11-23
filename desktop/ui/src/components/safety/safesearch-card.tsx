import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Save } from "lucide-react";
import { toast } from "sonner";

import { useSafeSearchConfig } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

const services = [
  { id: "google", label: "Google" },
  { id: "bing", label: "Bing" },
  { id: "duckduckgo", label: "DuckDuckGo" },
  { id: "ecosia", label: "Ecosia" },
  { id: "pixabay", label: "Pixabay" },
  { id: "yandex", label: "Yandex" },
  { id: "youtube", label: "YouTube" },
];

export function SafeSearchCard() {
  const config = useSafeSearchConfig();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [disabled, setDisabled] = useState<Set<string>>(new Set());
  const [ttl, setTtl] = useState(300);
  const configKey = JSON.stringify(config.data ?? null);

  useEffect(() => {
    if (!config.data) return;
    setEnabled(config.data.enabled);
    setDisabled(new Set(config.data.disabled));
    setTtl(config.data.ttl);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!config.data) return false;
    const source = new Set(config.data.disabled);
    if (enabled !== config.data.enabled || ttl !== config.data.ttl) return true;
    if (source.size !== disabled.size) return true;
    for (const id of disabled) if (!source.has(id)) return true;
    return false;
  }, [config.data, enabled, ttl, disabled]);

  const save = useMutation({
    mutationFn: () =>
      api.configureSafeSearch({ enabled, disabled: [...disabled], ttl }),
    onSuccess: () => {
      toast.success("强制安全搜索配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["safesearch-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const toggle = (id: string) =>
    setDisabled((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const enforced = services.length - disabled.size;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="强制安全搜索"
        description="把受支持搜索引擎的域名改写为严格安全搜索节点。"
        actions={
          <Badge tone={enabled ? "good" : "neutral"} dot>
            {enabled ? `已强制 ${enforced} 项` : "未启用"}
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {config.isLoading ? (
          <LoadingState label="正在加载安全搜索配置…" />
        ) : (
          <>
            <SwitchRow
              title="启用安全搜索"
              description="对下列服务强制返回安全搜索结果"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="mt-2">
              <div className="flex items-center justify-between">
                <span className="text-[12px] text-text">服务列表</span>
                <span className="text-[10.5px] text-text-3">
                  点击切换是否强制，灰色表示跳过
                </span>
              </div>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {services.map((service) => {
                  const active = !disabled.has(service.id);
                  return (
                    <button
                      key={service.id}
                      type="button"
                      disabled={!enabled}
                      aria-pressed={active}
                      onClick={() => toggle(service.id)}
                      className={cn(
                        "rounded-lg border px-2.5 py-1.5 text-[11.5px] transition-colors disabled:cursor-not-allowed disabled:opacity-50",
                        active
                          ? "border-good/25 bg-good-soft text-good"
                          : "border-border bg-surface-2 text-text-3 hover:bg-surface-3",
                      )}
                    >
                      {service.label}
                    </button>
                  );
                })}
              </div>
            </div>
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <Field label="重写 TTL（秒）" hint="安全搜索 CNAME 的缓存时间">
                <Input
                  type="number"
                  min={1}
                  max={86400}
                  value={ttl}
                  onChange={(event) => setTtl(Number(event.target.value))}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                部分服务（如 Youtube）可能使用独立域名或 IP 改写，请以实际解析结果为准。
              </div>
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
          disabled={!dirty || !Number.isFinite(ttl) || ttl <= 0}
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
