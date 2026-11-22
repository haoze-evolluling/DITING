import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { DatabaseZap, Save } from "lucide-react";
import { toast } from "sonner";

import { useCacheConfig } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import type { CacheConfig } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { Skeleton } from "../ui/skeleton";
import { SwitchRow } from "../ui/switch-row";

const modeOptions = [
  { value: "limit_max_ttl", label: "限制最大 TTL" },
  { value: "fixed_ttl", label: "固定 TTL" },
];

export function CacheConfigCard() {
  const config = useCacheConfig();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<CacheConfig | null>(null);
  const [exclude, setExclude] = useState("");
  const configKey = JSON.stringify(config.data ?? null);

  useEffect(() => {
    if (!config.data) return;
    setDraft({ ...config.data });
    setExclude(joinLines(config.data.excludePatterns));
    // 仅在服务端配置实际变化时重置草稿，避免轮询覆盖正在编辑的内容。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const excludeList = useMemo(() => parseLines(exclude), [exclude]);

  const dirty = useMemo(() => {
    if (!config.data || !draft) return false;
    const next = { ...draft, excludePatterns: excludeList, persistPath: draft.persistPath ?? "" };
    const source = {
      ...config.data,
      excludePatterns: config.data.excludePatterns ?? [],
      persistPath: config.data.persistPath ?? "",
    };
    return JSON.stringify(next) !== JSON.stringify(source);
  }, [config.data, draft, excludeList]);

  const save = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("配置尚未加载");
      return api.updateCacheConfig({
        ...draft,
        excludePatterns: excludeList,
        persistPath: draft.persistPath ?? "",
      });
    },
    onSuccess: () => {
      toast.success("缓存配置已更新并生效");
      void queryClient.invalidateQueries({ queryKey: ["cache-config"] });
      void queryClient.invalidateQueries({ queryKey: ["cache-stats"] });
      void queryClient.invalidateQueries({ queryKey: ["cache-persist"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<CacheConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const valid =
    draft &&
    draft.maxEntries >= 64 &&
    (draft.mode === "fixed_ttl"
      ? draft.fixedTtlSeconds > 0
      : draft.maxTtlSeconds > 0) &&
    (!draft.minTtlEnabled || draft.minTtlSeconds > 0) &&
    (!draft.staleFallbackEnabled || draft.staleFallbackSeconds > 0) &&
    (!draft.negativeTtlEnabled || draft.negativeTtlSeconds > 0) &&
    (!draft.prefetchEnabled ||
      (draft.prefetchThreshold > 0 && draft.prefetchBeforeExpiryMs >= 1_000)) &&
    (!draft.persistEnabled || (draft.persistIntervalSeconds ?? 0) >= 30);

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="缓存策略"
        description="条目容量、TTL 上落限、过期回退、预取与落盘持久化。"
        actions={<DatabaseZap className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {config.isLoading || !draft ? (
          <div className="space-y-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用智能缓存"
              description="关闭后所有查询直接转发上游"
              checked={draft.enabled}
              onCheckedChange={(enabled) => update({ enabled })}
            />
            <SwitchRow
              title="乐观返回"
              description="过期条目在后台刷新时先返回旧结果"
              checked={draft.optimistic}
              onCheckedChange={(optimistic) => update({ optimistic })}
            />

            <div className="mt-2 grid gap-3 sm:grid-cols-2">
              <Field label="条目容量" hint="最多保留的缓存条目数">
                <Input
                  type="number"
                  min={64}
                  max={1_000_000}
                  value={draft.maxEntries}
                  onChange={(event) => update({ maxEntries: Number(event.target.value) })}
                />
              </Field>
              <Field label="TTL 模式" hint="限制上游 TTL 或统一固定">
                <Select
                  value={draft.mode}
                  options={modeOptions}
                  onValueChange={(mode) => update({ mode })}
                  ariaLabel="缓存 TTL 模式"
                />
              </Field>
              {draft.mode === "fixed_ttl" ? (
                <Field label="固定 TTL（秒）" hint="所有应答统一使用该 TTL">
                  <Input
                    type="number"
                    min={1}
                    max={86400}
                    value={draft.fixedTtlSeconds}
                    onChange={(event) =>
                      update({ fixedTtlSeconds: Number(event.target.value) })
                    }
                  />
                </Field>
              ) : (
                <Field label="最大 TTL（秒）" hint="超过该值的上游 TTL 会被截断">
                  <Input
                    type="number"
                    min={1}
                    max={86400}
                    value={draft.maxTtlSeconds}
                    onChange={(event) =>
                      update({ maxTtlSeconds: Number(event.target.value) })
                    }
                  />
                </Field>
              )}
            </div>

            <div className="mt-1 space-y-1">
              <SwitchRow
                title="设置最小 TTL"
                description="抬高上游返回过短的 TTL"
                checked={draft.minTtlEnabled}
                onCheckedChange={(minTtlEnabled) => update({ minTtlEnabled })}
              />
              {draft.minTtlEnabled ? (
                <div className="grid gap-3 pb-2 sm:grid-cols-2">
                  <Field label="最小 TTL（秒）">
                    <Input
                      type="number"
                      min={1}
                      max={86400}
                      value={draft.minTtlSeconds}
                      onChange={(event) =>
                        update({ minTtlSeconds: Number(event.target.value) })
                      }
                    />
                  </Field>
                </div>
              ) : null}
              <SwitchRow
                title="过期回退"
                description="上游失败时继续使用已过期条目"
                checked={draft.staleFallbackEnabled}
                onCheckedChange={(staleFallbackEnabled) => update({ staleFallbackEnabled })}
              />
              {draft.staleFallbackEnabled ? (
                <div className="grid gap-3 pb-2 sm:grid-cols-2">
                  <Field label="回退时长（秒）">
                    <Input
                      type="number"
                      min={1}
                      max={86400}
                      value={draft.staleFallbackSeconds}
                      onChange={(event) =>
                        update({ staleFallbackSeconds: Number(event.target.value) })
                      }
                    />
                  </Field>
                </div>
              ) : null}
              <SwitchRow
                title="缓存否定应答"
                description="缓存 NXDOMAIN 与 NODATA 结果"
                checked={draft.negativeTtlEnabled}
                onCheckedChange={(negativeTtlEnabled) => update({ negativeTtlEnabled })}
              />
              {draft.negativeTtlEnabled ? (
                <div className="grid gap-3 pb-2 sm:grid-cols-2">
                  <Field label="否定 TTL（秒）">
                    <Input
                      type="number"
                      min={1}
                      max={3600}
                      value={draft.negativeTtlSeconds}
                      onChange={(event) =>
                        update({ negativeTtlSeconds: Number(event.target.value) })
                      }
                    />
                  </Field>
                </div>
              ) : null}
              <SwitchRow
                title="热点预取"
                description="在条目过期前主动向上游刷新"
                checked={draft.prefetchEnabled}
                onCheckedChange={(prefetchEnabled) => update({ prefetchEnabled })}
              />
              {draft.prefetchEnabled ? (
                <div className="grid gap-3 pb-2 sm:grid-cols-2">
                  <Field label="命中阈值" hint="达到该命中次数后参与预取">
                    <Input
                      type="number"
                      min={1}
                      max={100000}
                      value={draft.prefetchThreshold}
                      onChange={(event) =>
                        update({ prefetchThreshold: Number(event.target.value) })
                      }
                    />
                  </Field>
                  <Field label="提前量（毫秒）" hint="1000 – 3600000">
                    <Input
                      type="number"
                      min={1000}
                      max={3600000}
                      step={1000}
                      value={draft.prefetchBeforeExpiryMs}
                      onChange={(event) =>
                        update({ prefetchBeforeExpiryMs: Number(event.target.value) })
                      }
                    />
                  </Field>
                </div>
              ) : null}
            </div>

            <Field
              label="排除规则"
              hint="每行一个域名或通配符，命中后不写入缓存。"
              className="mt-1"
            >
              <Textarea
                className="mono min-h-[72px] text-[11.5px]"
                value={exclude}
                spellCheck={false}
                placeholder={"*.local\nlocalhost"}
                onChange={(event) => setExclude(event.target.value)}
              />
            </Field>

            <div className="mt-1 space-y-1">
              <SwitchRow
                title="落盘持久化"
                description="定期把缓存写入磁盘，服务重启后可恢复"
                checked={draft.persistEnabled}
                onCheckedChange={(persistEnabled) =>
                  update({
                    persistEnabled,
                    persistIntervalSeconds:
                      persistEnabled && !draft.persistIntervalSeconds
                        ? 300
                        : draft.persistIntervalSeconds,
                  })
                }
              />
              {draft.persistEnabled ? (
                <div className="grid gap-3 pb-2">
                  <Field label="落盘间隔（秒）" hint="30 – 86400 秒">
                    <Input
                      type="number"
                      min={30}
                      max={86400}
                      value={draft.persistIntervalSeconds ?? 0}
                      onChange={(event) =>
                        update({ persistIntervalSeconds: Number(event.target.value) })
                      }
                    />
                  </Field>
                  <Field label="文件路径" hint="留空使用默认数据目录下的 cache.json">
                    <Input
                      className="mono text-[11.5px]"
                      value={draft.persistPath ?? ""}
                      placeholder="默认：数据目录/cache.json"
                      onChange={(event) => update({ persistPath: event.target.value })}
                    />
                  </Field>
                </div>
              ) : null}
            </div>

            {!valid ? (
              <p className="rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                容量、TTL、预取与落盘间隔超出允许范围，修正后才能保存。
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
