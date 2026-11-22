import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { FileCode2, FlaskConical, Pencil, Plus, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { useZoneConfig } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import type { ZoneEntry, ZoneTestResponse } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { EmptyState } from "../ui/empty";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { Skeleton } from "../ui/skeleton";
import { SwitchRow } from "../ui/switch-row";

function ZoneDialog({
  open,
  onOpenChange,
  initial,
  onSubmit,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ZoneEntry | null;
  onSubmit: (zone: ZoneEntry) => void;
}) {
  const [origin, setOrigin] = useState("");
  const [content, setContent] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [test, setTest] = useState<ZoneTestResponse | null>(null);
  const [testError, setTestError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setOrigin(initial?.origin ?? "");
    setContent(initial?.content ?? "");
    setEnabled(initial?.enabled ?? true);
    setTest(null);
    setTestError(null);
  }, [open, initial]);

  const runTest = useMutation({
    mutationFn: () => api.testZone(origin.trim(), content, 0),
    onSuccess: (result) => {
      setTest(result);
      setTestError(result.success ? null : result.error ?? "区解析失败");
    },
    onError: (error) => {
      setTest(null);
      setTestError(describeError(error));
    },
  });

  const valid = origin.trim().length > 0 && content.trim().length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(640px,calc(100vw-40px))]">
        <DialogHeader
          title={initial ? "编辑区文件" : "添加区文件"}
          description="粘贴 BIND 风格的区文本，保存后由内置权威解析器直接应答。"
        />
        <DialogBody className="space-y-3.5">
          <Field label="区原点" hint="例如 home.lan">
            <Input
              className="mono"
              value={origin}
              placeholder="home.lan"
              onChange={(event) => setOrigin(event.target.value)}
            />
          </Field>
          <Field label="区文本" hint="支持 A / AAAA / CNAME / MX / TXT / SRV / PTR 等记录与 $TTL">
            <Textarea
              className="mono min-h-[220px] text-[11px] leading-5"
              value={content}
              spellCheck={false}
              placeholder={"$TTL 300\n@   IN SOA ns.home.lan. admin.home.lan. (1 3600 600 86400 300)\n@   IN NS  ns.home.lan.\nns  IN A   192.168.1.2\nwww IN A   192.168.1.10"}
              onChange={(event) => setContent(event.target.value)}
            />
          </Field>
          <SwitchRow
            title="启用该区"
            checked={enabled}
            onCheckedChange={setEnabled}
          />
          {testError ? (
            <p className="rounded-lg bg-danger-soft px-3 py-2 text-[11px] leading-5 text-danger">
              {testError}
            </p>
          ) : test ? (
            <div className="rounded-lg bg-good-soft px-3 py-2 text-[11px] leading-5 text-good">
              解析通过，共 {test.records.length} 条记录
            </div>
          ) : null}
        </DialogBody>
        <DialogFooter className="justify-between">
          <Button
            variant="ghost"
            loading={runTest.isPending}
            disabled={!valid}
            onClick={() => runTest.mutate()}
          >
            <FlaskConical className="h-3.5 w-3.5" />
            测试解析
          </Button>
          <div className="flex items-center gap-2">
            <Button variant="ghost" onClick={() => onOpenChange(false)}>
              取消
            </Button>
            <Button
              variant="primary"
              disabled={!valid}
              onClick={() => {
                onSubmit({
                  id: initial?.id ?? "",
                  origin: origin.trim(),
                  content,
                  enabled,
                });
                onOpenChange(false);
              }}
            >
              保存
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function ZoneCard() {
  const config = useZoneConfig();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [ttl, setTtl] = useState(300);
  const [zones, setZones] = useState<ZoneEntry[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ZoneEntry | null>(null);
  const configKey = JSON.stringify(
    config.data ? { enabled: config.data.enabled, ttl: config.data.ttl, zones: config.data.zones } : null,
  );

  useEffect(() => {
    if (!config.data) return;
    setEnabled(config.data.enabled);
    setTtl(config.data.ttl);
    setZones(config.data.zones.map((zone) => ({ ...zone })));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!config.data) return false;
    return (
      enabled !== config.data.enabled ||
      ttl !== config.data.ttl ||
      JSON.stringify(zones) !== JSON.stringify(config.data.zones)
    );
  }, [config.data, enabled, ttl, zones]);

  const save = useMutation({
    mutationFn: () => api.configureZone({ enabled, ttl, zones }),
    onSuccess: () => {
      toast.success("区文件配置已保存并生效");
      void queryClient.invalidateQueries({ queryKey: ["zone-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const submit = (zone: ZoneEntry) => {
    setZones((current) => {
      const index = current.findIndex((entry) => entry.id === editing?.id);
      if (index < 0) return [...current, zone];
      return current.map((entry, position) => (position === index ? zone : entry));
    });
    setEditing(null);
  };

  const stateFor = (zone: ZoneEntry) =>
    config.data?.states.find(
      (state) => state.id === zone.id || state.origin === zone.origin,
    );

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="区文件"
        description={`用本地区数据为内网域名提供权威解析，最多 ${
          config.data?.maxZones ?? 32
        } 个区。`}
        actions={
          <Button
            size="sm"
            variant="secondary"
            disabled={zones.length >= (config.data?.maxZones ?? 64)}
            onClick={() => {
              setEditing(null);
              setDialogOpen(true);
            }}
          >
            <Plus className="h-3.5 w-3.5" />
            添加区
          </Button>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {config.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用区文件解析"
              description="关闭后所有区暂停，内网域名回退到上游"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="grid gap-3 border-b border-border/60 py-2.5 sm:grid-cols-2">
              <Field label="默认 TTL（秒）" hint="区文本未声明时的默认值">
                <Input
                  type="number"
                  min={1}
                  max={86400}
                  value={ttl}
                  onChange={(event) => setTtl(Number(event.target.value))}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                已启用 {zones.filter((zone) => zone.enabled).length} / {zones.length} 个区
                {config.data ? ` · 上限 ${config.data.maxZones} 个区` : ""}
              </div>
            </div>

            <div className="mt-2 min-h-0 flex-1">
              {zones.length === 0 ? (
                <EmptyState
                  icon={FileCode2}
                  title="还没有区文件"
                  description="添加内网域名区，让局域网设备获得权威解析结果。"
                  action={
                    <Button
                      size="sm"
                      variant="primary"
                      onClick={() => {
                        setEditing(null);
                        setDialogOpen(true);
                      }}
                    >
                      <Plus className="h-3.5 w-3.5" />
                      添加区
                    </Button>
                  }
                />
              ) : (
                <div className="max-h-[340px] divide-y divide-border/70 overflow-y-auto pr-1">
                  {zones.map((zone, index) => {
                    const state = stateFor(zone);
                    return (
                      <div key={zone.id || `${zone.origin}-${index}`} className="flex items-start gap-3 py-2.5">
                        <span className="mt-1.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg bg-surface-3 text-text-3">
                          <FileCode2 className="h-3 w-3" />
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="mono truncate text-[12px] text-text">{zone.origin}</span>
                            <Badge tone={zone.enabled ? "good" : "neutral"}>
                              {zone.enabled ? "启用" : "停用"}
                            </Badge>
                            {state ? (
                              <Badge tone={state.loaded ? "accent" : "danger"}>
                                {state.loaded ? `${state.records} 条记录` : "解析失败"}
                              </Badge>
                            ) : null}
                          </div>
                          {state?.error ? (
                            <div className="mt-1 text-[10.5px] text-danger">{state.error}</div>
                          ) : null}
                        </div>
                        <div className="flex shrink-0 items-center gap-0.5">
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`编辑 ${zone.origin}`}
                            onClick={() => {
                              setEditing(zone);
                              setDialogOpen(true);
                            }}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`删除 ${zone.origin}`}
                            onClick={() =>
                              setZones((current) => current.filter((entry) => entry !== zone))
                            }
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
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

      <ZoneDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open);
          if (!open) setEditing(null);
        }}
        initial={editing}
        onSubmit={submit}
      />
    </Card>
  );
}
