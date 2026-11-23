import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  FlaskConical,
  Globe2,
  Pencil,
  Plus,
  RefreshCw,
  Save,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "../components/layout/page-header";
import { BootstrapCard } from "../components/upstreams/bootstrap-card";
import { ProviderDialog } from "../components/upstreams/provider-dialog";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../components/ui/card";
import { ConfirmDialog } from "../components/ui/confirm-dialog";
import { ListRowsSkeleton } from "../components/skeletons/parts";
import { EmptyState } from "../components/ui/empty";
import { Segmented } from "../components/ui/segmented";
import { useUpstreamConfig } from "../hooks/use-api";
import { api, describeError } from "../lib/api";
import { formatLatency } from "../lib/format";
import { protocolLabel, resolverModeOptions } from "../lib/labels";
import type { ProviderConfig, UpstreamTestResult } from "../lib/types";
import { cn } from "../lib/cn";

interface TestState {
  loading: boolean;
  result?: UpstreamTestResult;
  error?: string;
}

export function UpstreamPage() {
  const config = useUpstreamConfig();
  const queryClient = useQueryClient();
  const [mode, setMode] = useState("primary_backup");
  const [providers, setProviders] = useState<ProviderConfig[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ProviderConfig | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ProviderConfig | null>(null);
  const [tests, setTests] = useState<Record<string, TestState>>({});
  const configKey = JSON.stringify(
    config.data ? { mode: config.data.mode, providers: config.data.providers } : null,
  );

  useEffect(() => {
    if (!config.data) return;
    setMode(config.data.mode);
    setProviders(config.data.providers.map((provider) => ({ ...provider })));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!config.data) return false;
    return (
      mode !== config.data.mode ||
      JSON.stringify(providers) !== JSON.stringify(config.data.providers)
    );
  }, [config.data, mode, providers]);

  const save = useMutation({
    mutationFn: () => api.configureUpstream({ mode, providers }),
    onSuccess: () => {
      toast.success("上游解析配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["upstream-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const testProvider = async (provider: ProviderConfig) => {
    const key = provider.id;
    setTests((current) => ({ ...current, [key]: { loading: true } }));
    try {
      const result = await api.testUpstream(provider);
      setTests((current) => ({ ...current, [key]: { loading: false, result } }));
      if (result.success) toast.success(`${provider.id} 测试通过 · ${formatLatency(result.latencyMs)}`);
      else toast.error(`${provider.id} 测试失败：${result.error ?? "未知错误"}`);
    } catch (error) {
      const message = describeError(error);
      setTests((current) => ({ ...current, [key]: { loading: false, error: message } }));
      toast.error(message);
    }
  };

  const testAll = async () => {
    for (const provider of providers) {
      await testProvider(provider);
    }
  };

  const submitProvider = (provider: ProviderConfig) => {
    setProviders((current) => {
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
    setProviders((current) => current.filter((item) => item.id !== deleteTarget.id));
    setDeleteTarget(null);
    toast.success("已从草稿移除，保存后生效");
  };

  const refresh = () => {
    void config.refetch();
    setTests({});
  };

  return (
    <>
      <PageHeader
        title="上游解析"
        description="调度策略、上游服务器与 Bootstrap 引导解析"
        actions={
          <>
            <Button size="sm" variant="ghost" onClick={refresh} loading={config.isFetching}>
              <RefreshCw className="h-3.5 w-3.5" />
              刷新
            </Button>
            <Button
              size="sm"
              variant="primary"
              disabled={!dirty || providers.length === 0}
              loading={save.isPending}
              onClick={() => save.mutate()}
            >
              <Save className="h-3.5 w-3.5" />
              保存配置
            </Button>
          </>
        }
      />

      <div className="space-y-3.5">
        <Card>
          <CardHeader
            title="解析策略"
            description="决定多个上游之间的选择与回退方式。"
          />
          <CardContent className="pt-1">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <Segmented
                value={mode}
                options={resolverModeOptions.map((option) => ({
                  value: option.value,
                  label: option.label,
                }))}
                onChange={setMode}
              />
              <span className="text-[11px] text-text-3">
                当前 {providers.length} 个上游
                {providers.filter((provider) => (provider.weight ?? 1) > 1).length > 0
                  ? " · 已设置权重"
                  : ""}
              </span>
            </div>
          </CardContent>
        </Card>

        <div className="card-grid-2">
          <Card className="flex flex-col">
            <CardHeader
              title="上游服务器"
              description="名称唯一；可测试连通性并固定证书指纹。"
              actions={
                <>
                  <Button size="sm" variant="ghost" onClick={() => void testAll()} disabled={providers.length === 0}>
                    <FlaskConical className="h-3.5 w-3.5" />
                    全部测试
                  </Button>
                  <Button size="sm" variant="secondary" onClick={addProvider}>
                    <Plus className="h-3.5 w-3.5" />
                    添加
                  </Button>
                </>
              }
            />
            <CardContent className="flex flex-1 flex-col pt-2">
              {config.isLoading ? (
                <ListRowsSkeleton rows={3} />
              ) : providers.length === 0 ? (
                <EmptyState
                  icon={Globe2}
                  title="尚未配置上游"
                  description="至少添加一个上游 DNS，服务才能对外解析。"
                  action={
                    <Button size="sm" variant="primary" onClick={addProvider}>
                      <Plus className="h-3.5 w-3.5" />
                      添加上游
                    </Button>
                  }
                />
              ) : (
                <div className="divide-y divide-border/70">
                  {providers.map((provider) => {
                    const test = tests[provider.id];
                    return (
                      <div key={provider.id} className="flex items-start gap-3 py-3">
                        <span
                          className={cn(
                            "mt-2 h-1.5 w-1.5 shrink-0 rounded-full",
                            test?.loading
                              ? "animate-pulse bg-warn"
                              : test?.result?.success
                                ? "bg-good"
                                : test?.result || test?.error
                                  ? "bg-danger"
                                  : "bg-text-3",
                          )}
                        />
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="truncate text-[12.5px] font-medium text-text">
                              {provider.id}
                            </span>
                            <Badge tone="neutral">{protocolLabel(provider.protocol)}</Badge>
                            {(provider.weight ?? 1) > 1 ? (
                              <Badge tone="accent">权重 {provider.weight}</Badge>
                            ) : null}
                            {provider.pin ? <Badge tone="violet">指纹固定</Badge> : null}
                          </div>
                          <div className="mono mt-1 truncate text-[10.5px] text-text-3">
                            {provider.server || provider.url || "—"}
                          </div>
                          {test && !test.loading ? (
                            <div
                              className={cn(
                                "mt-1 text-[10.5px]",
                                test.result?.success ? "text-good" : "text-danger",
                              )}
                            >
                              {test.result?.success
                                ? `连接正常 · ${formatLatency(test.result.latencyMs)}`
                                : test.error ?? test.result?.error ?? "连接失败"}
                            </div>
                          ) : null}
                        </div>
                        <div className="flex shrink-0 items-center gap-0.5">
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`测试 ${provider.id}`}
                            loading={test?.loading}
                            onClick={() => void testProvider(provider)}
                          >
                            <FlaskConical className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`编辑 ${provider.id}`}
                            onClick={() => editProvider(provider)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`删除 ${provider.id}`}
                            onClick={() => setDeleteTarget(provider)}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
            <CardFooter>
              <span className="text-[10.5px] text-text-3">
                {dirty ? "存在未保存的修改" : "配置已与运行服务同步"}
              </span>
              <Button
                size="sm"
                variant="primary"
                disabled={!dirty || providers.length === 0}
                loading={save.isPending}
                onClick={() => save.mutate()}
              >
                <Save className="h-3.5 w-3.5" />
                保存
              </Button>
            </CardFooter>
          </Card>

          <BootstrapCard config={config.data?.bootstrap} loading={config.isLoading} />
        </div>
      </div>

      <ProviderDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        initial={editing}
        onSubmit={submitProvider}
      />

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="移除上游"
        description={`确定要从配置中移除「${deleteTarget?.id ?? ""}」吗？保存后才会生效。`}
        confirmLabel="移除"
        onConfirm={removeProvider}
      />
    </>
  );
}
