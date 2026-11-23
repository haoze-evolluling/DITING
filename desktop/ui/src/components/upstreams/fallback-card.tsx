import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeftRight, FlaskConical, Plus, Save } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import type { ProviderConfig, ResolverConfig } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { EmptyState } from "../ui/empty";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";
import { ProviderDialog } from "./provider-dialog";
import { ProviderRow, type TestState } from "./provider-row";

const rcodeOptions = [
  { value: 2, label: "SERVFAIL" },
  { value: 5, label: "REFUSED" },
  { value: 3, label: "NXDOMAIN" },
  { value: 1, label: "FORMERR" },
];

function normalizeProvider(provider: ProviderConfig): ProviderConfig {
  return {
    id: provider.id.trim(),
    protocol: (provider.protocol ?? "").toUpperCase(),
    server: provider.server.trim(),
    url: provider.url.trim(),
    weight: Number(provider.weight) > 0 ? Number(provider.weight) : 1,
    pin: (provider.pin ?? "").trim(),
  };
}

function canonicalProviders(providers: ProviderConfig[]): string {
  return JSON.stringify(providers.map(normalizeProvider));
}

function canonicalCodes(codes: number[]): string {
  return JSON.stringify([...codes].sort((left, right) => left - right));
}

export function FallbackCard({
  config,
  providers,
  loading,
}: {
  config?: ResolverConfig;
  providers: ProviderConfig[];
  loading: boolean;
}) {
  const queryClient = useQueryClient();
  const [fallbackProviders, setFallbackProviders] = useState<ProviderConfig[]>([]);
  const [timeoutMs, setTimeoutMs] = useState("0");
  const [rcodes, setRcodes] = useState<number[]>([]);
  const [onError, setOnError] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ProviderConfig | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ProviderConfig | null>(null);
  const [tests, setTests] = useState<Record<string, TestState>>({});

  const serverTimeout = config?.fallbackTimeoutMs ?? 0;
  const serverRcodes = config?.fallbackOnRcode ?? [2, 5];
  const serverOnError = config?.fallbackOnError ?? true;
  const configKey = JSON.stringify([
    config?.fallbackProviders ?? [],
    serverTimeout,
    serverRcodes,
    serverOnError,
  ]);

  useEffect(() => {
    if (!config) return;
    setFallbackProviders((config.fallbackProviders ?? []).map((provider) => ({ ...provider })));
    setTimeoutMs(String(config.fallbackTimeoutMs ?? 0));
    setRcodes([...(config.fallbackOnRcode ?? [2, 5])]);
    setOnError(config.fallbackOnError ?? true);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const mainIds = useMemo(
    () => new Set(providers.map((provider) => provider.id.trim())),
    [providers],
  );

  const conflicts = useMemo(() => {
    const issues: string[] = [];
    const ids = fallbackProviders.map((provider) => provider.id.trim());
    for (const id of ids) {
      if (mainIds.has(id)) issues.push(`回退上游与主链路同名：${id}`);
    }
    const seen = new Set<string>();
    for (const id of ids) {
      if (seen.has(id)) issues.push(`回退上游名称重复：${id}`);
      seen.add(id);
    }
    return [...new Set(issues)];
  }, [fallbackProviders, mainIds]);

  const timeoutValue = Number(timeoutMs.trim() || 0);
  const timeoutValid =
    Number.isInteger(timeoutValue) &&
    (timeoutValue === 0 || (timeoutValue >= 100 && timeoutValue <= 30000));

  const dirty =
    canonicalProviders(fallbackProviders) !==
      canonicalProviders(config?.fallbackProviders ?? []) ||
    timeoutValue !== serverTimeout ||
    canonicalCodes(rcodes) !== canonicalCodes(serverRcodes) ||
    onError !== serverOnError;

  const save = useMutation({
    mutationFn: () =>
      api.configureUpstream({
        fallbackProviders: fallbackProviders.map(normalizeProvider),
        fallbackTimeoutMs: timeoutValue,
        fallbackOnRcode: rcodes,
        fallbackOnError: onError,
      }),
    onSuccess: () => {
      toast.success("回退上游配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["upstream-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const testProvider = async (provider: ProviderConfig) => {
    setTests((current) => ({ ...current, [provider.id]: { loading: true } }));
    try {
      const result = await api.testUpstream(provider);
      setTests((current) => ({ ...current, [provider.id]: { loading: false, result } }));
      if (result.success) toast.success(`${provider.id} 测试通过`);
      else toast.error(`${provider.id} 测试失败：${result.error ?? "未知错误"}`);
    } catch (error) {
      const message = describeError(error);
      setTests((current) => ({
        ...current,
        [provider.id]: { loading: false, error: message },
      }));
      toast.error(message);
    }
  };

  const testAll = async () => {
    for (const provider of fallbackProviders) {
      await testProvider(provider);
    }
  };

  const submitProvider = (provider: ProviderConfig) => {
    const id = provider.id.trim();
    if (mainIds.has(id)) {
      toast.error(`回退上游不能与主链路上游同名：${id}`);
      return;
    }
    const clash = fallbackProviders.some(
      (item) => item.id.trim() === id && item.id !== editing?.id,
    );
    if (clash) {
      toast.error(`回退上游名称重复：${id}`);
      return;
    }
    setFallbackProviders((current) => {
      const index = current.findIndex((item) => item.id === editing?.id);
      if (index < 0) return [...current, provider];
      return current.map((item, position) => (position === index ? provider : item));
    });
    setEditing(null);
  };

  const addProvider = () => {
    setEditing(null);
    setDialogOpen(true);
  };

  const editProvider = (provider: ProviderConfig) => {
    setEditing(provider);
    setDialogOpen(true);
  };

  const removeProvider = () => {
    if (!deleteTarget) return;
    setFallbackProviders((current) =>
      current.filter((item) => item.id !== deleteTarget.id),
    );
    setDeleteTarget(null);
    toast.success("已从草稿移除，保存后生效");
  };

  const toggleCode = (code: number) =>
    setRcodes((current) =>
      current.includes(code)
        ? current.filter((value) => value !== code)
        : [...current, code],
    );

  const valid = conflicts.length === 0 && timeoutValid;

  return (
    <>
      <Card className="flex flex-col">
        <CardHeader
          title="独立回退上游"
          description="主链路整体失效后整链切换的备用解析链路。"
          actions={
            <>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => void testAll()}
                disabled={fallbackProviders.length === 0}
              >
                <FlaskConical className="h-3.5 w-3.5" />
                全部测试
              </Button>
              <Button size="sm" variant="secondary" onClick={addProvider} disabled={loading}>
                <Plus className="h-3.5 w-3.5" />
                添加回退节点
              </Button>
            </>
          }
        />
        <CardContent className="flex flex-1 flex-col pt-2">
          {loading ? (
            <LoadingState label="正在加载回退配置…" />
          ) : fallbackProviders.length === 0 ? (
            <EmptyState
              icon={ArrowLeftRight}
              title="未配置回退上游"
              description="未启用回退链时 DNS 查询量不会因此增加。"
              action={
                <Button size="sm" variant="primary" onClick={addProvider}>
                  <Plus className="h-3.5 w-3.5" />
                  添加回退节点
                </Button>
              }
            />
          ) : (
            <>
              <div className="divide-y divide-border/70">
                {fallbackProviders.map((provider) => (
                  <ProviderRow
                    key={provider.id}
                    provider={provider}
                    test={tests[provider.id]}
                    onTest={() => void testProvider(provider)}
                    onEdit={() => editProvider(provider)}
                    onDelete={() => setDeleteTarget(provider)}
                  />
                ))}
              </div>

              <div className="mt-2 grid grid-cols-1 gap-3 sm:grid-cols-2">
                <Field
                  label="主链路独立超时（毫秒）"
                  hint="0 表示使用默认 2000ms；有效范围 100–30000。"
                >
                  <Input
                    type="number"
                    min={0}
                    max={30000}
                    value={timeoutMs}
                    onChange={(event) => setTimeoutMs(event.target.value)}
                  />
                </Field>
                <div>
                  <span className="text-[12px] text-text">触发回退的应答码</span>
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    {rcodeOptions.map((option) => {
                      const active = rcodes.includes(option.value);
                      return (
                        <button
                          key={option.value}
                          type="button"
                          aria-pressed={active}
                          onClick={() => toggleCode(option.value)}
                          className={cn(
                            "h-8 rounded-lg border px-2.5 text-[11.5px] transition-colors",
                            active
                              ? "border-accent bg-accent-soft text-accent"
                              : "border-border bg-surface-2 text-text-3 hover:bg-surface-3",
                          )}
                        >
                          {option.label}
                        </button>
                      );
                    })}
                  </div>
                  <span className="mt-1 block text-[10.5px] text-text-3">
                    {rcodes.length === 0
                      ? "未选择应答码时，仅在超时或连接失败时回退。"
                      : "NXDOMAIN 属于权威答案，谨慎勾选。"}
                  </span>
                </div>
              </div>

              <SwitchRow
                className="mt-1"
                title="超时与连接失败也触发回退"
                description="主链路超时或网络错误时整链切换到回退上游"
                checked={onError}
                onCheckedChange={setOnError}
              />

              <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] leading-4 text-text-3">
                与主链路是两条独立链路：主链路先以独立超时尝试整条链，失败或命中上述应答码后，才整链切换到回退上游。
              </p>
            </>
          )}

          {conflicts.length > 0 ? (
            <div className="mt-3 space-y-1 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
              {conflicts.map((conflict) => (
                <p key={conflict}>{conflict}</p>
              ))}
            </div>
          ) : null}
          {!timeoutValid ? (
            <p className="mt-3 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
              主链路超时需为 0，或处于 100–30000 毫秒之间。
            </p>
          ) : null}
        </CardContent>
        <CardFooter>
          <span className="text-[10.5px] text-text-3">
            {dirty ? "存在未保存的修改" : "配置已与运行服务同步"}
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

      <ProviderDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        initial={editing}
        onSubmit={submitProvider}
      />

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="移除回退上游"
        description={`确定要从回退链中移除「${deleteTarget?.id ?? ""}」吗？保存后才会生效。`}
        confirmLabel="移除"
        onConfirm={removeProvider}
      />
    </>
  );
}
