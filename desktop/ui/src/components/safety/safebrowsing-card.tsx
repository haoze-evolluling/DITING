import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { BadgeCheck, Save } from "lucide-react";
import { toast } from "sonner";

import { useSafeBrowsing } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber } from "../../lib/format";
import type { SafeBrowsingConfig } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { Skeleton } from "../ui/skeleton";
import { SwitchRow } from "../ui/switch-row";

const blockModeLabels: Record<string, string> = {
  null_ip: "返回空地址",
  nxdomain: "NXDOMAIN",
  refused: "REFUSED",
};

export function SafeBrowsingCard() {
  const data = useSafeBrowsing();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<SafeBrowsingConfig | null>(null);
  const configKey = JSON.stringify(data.data?.config ?? null);

  useEffect(() => {
    if (!data.data) return;
    setDraft({ ...data.data.config });
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(
    () =>
      Boolean(data.data && draft) &&
      JSON.stringify(draft) !== JSON.stringify(data.data?.config),
    [data.data, draft],
  );

  const save = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("配置尚未加载");
      return api.configureSafeBrowsing({
        enabled: draft.enabled,
        parentalEnabled: draft.parentalEnabled,
        timeoutMs: draft.timeoutMs,
        cacheSize: draft.cacheSize,
        cacheTtlSeconds: draft.cacheTTLSeconds,
      });
    },
    onSuccess: () => {
      toast.success("声誉查询配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["safebrowsing"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<SafeBrowsingConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const valid =
    draft &&
    draft.timeoutMs >= 100 &&
    draft.timeoutMs <= 30_000 &&
    draft.cacheSize >= 0 &&
    draft.cacheTTLSeconds > 0;

  const stats = data.data?.stats;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="安全浏览与家长控制"
        description="通过上游威胁情报拦截恶意域名，并接受家长控制策略。"
        actions={<BadgeCheck className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {data.isLoading || !draft ? (
          <div className="space-y-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-20 w-full" />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用安全浏览"
              description="把域名提交到声誉服务并拦截命中结果"
              checked={draft.enabled}
              onCheckedChange={(enabled) => update({ enabled })}
            />
            <SwitchRow
              title="家长控制"
              description="启用上游提供的成人内容过滤策略"
              checked={draft.parentalEnabled}
              onCheckedChange={(parentalEnabled) => update({ parentalEnabled })}
              disabled={!draft.enabled}
            />

            <div className="mt-2 grid gap-3 sm:grid-cols-3">
              <Field label="查询超时（毫秒）" hint="100 – 30000">
                <Input
                  type="number"
                  min={100}
                  max={30000}
                  step={100}
                  value={draft.timeoutMs}
                  onChange={(event) => update({ timeoutMs: Number(event.target.value) })}
                />
              </Field>
              <Field label="缓存条目" hint="0 表示禁用结果缓存">
                <Input
                  type="number"
                  min={0}
                  max={1_000_000}
                  value={draft.cacheSize}
                  onChange={(event) => update({ cacheSize: Number(event.target.value) })}
                />
              </Field>
              <Field label="缓存 TTL（秒）">
                <Input
                  type="number"
                  min={1}
                  max={86400}
                  value={draft.cacheTTLSeconds}
                  onChange={(event) => update({ cacheTTLSeconds: Number(event.target.value) })}
                />
              </Field>
            </div>

            <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
              {[
                { label: "累计查询", value: stats?.lookups },
                { label: "缓存命中", value: stats?.cacheHits },
                { label: "已拦截", value: stats?.blocked },
                { label: "失败", value: stats?.failures },
              ].map((item) => (
                <div
                  key={item.label}
                  className="rounded-xl border border-border bg-surface-2 px-3 py-2"
                >
                  <div className="text-[10px] text-text-3">{item.label}</div>
                  <div className="num mt-0.5 text-[15px] font-semibold text-text">
                    {formatNumber(item.value)}
                  </div>
                </div>
              ))}
            </div>

            {data.data ? (
              <div className="mt-2 flex flex-wrap items-center gap-2 text-[10.5px] text-text-3">
                <span>拦截方式</span>
                <Badge tone="neutral">
                  {blockModeLabels[data.data.blockMode] ?? data.data.blockMode}
                </Badge>
                <span className="mono">{data.data.blockingIPv4}</span>
                <span className="mono">{data.data.blockingIPv6}</span>
              </div>
            ) : null}

            {!valid ? (
              <p className="mt-2 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                超时需在 100 – 30000 毫秒之间，缓存条目不可为负，TTL 需大于 0。
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
          disabled={!dirty || !valid}
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
