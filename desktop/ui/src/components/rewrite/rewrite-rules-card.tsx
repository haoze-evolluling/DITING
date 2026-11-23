import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Edit3, Pencil, Plus, Save, Trash2, Waypoints } from "lucide-react";
import { toast } from "sonner";

import { useRewriteRules, useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import type { RewriteRule } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { EmptyState } from "../ui/empty";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";
import { RewriteRuleDialog } from "./rewrite-rule-dialog";

function ruleTags(rule: RewriteRule): { label: string; tone: "accent" | "good" | "violet" | "warn" }[] {
  const tags: { label: string; tone: "accent" | "good" | "violet" | "warn" }[] = [];
  if (rule.ips && rule.ips.length > 0) {
    tags.push({ label: `地址 ${rule.ips.length}`, tone: "accent" });
  }
  if (rule.cname) tags.push({ label: "CNAME", tone: "good" });
  if (rule.txt && rule.txt.length > 0) tags.push({ label: `TXT ${rule.txt.length}`, tone: "violet" });
  if (rule.records && rule.records.length > 0) {
    tags.push({ label: `记录 ${rule.records.length}`, tone: "warn" });
  }
  if (rule.rcode) tags.push({ label: rule.rcode, tone: "warn" });
  if (rule.ttl) tags.push({ label: `TTL ${rule.ttl}s`, tone: "accent" });
  return tags;
}

export function RewriteRulesCard() {
  const status = useStatus();
  const rules = useRewriteRules();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [ttl, setTtl] = useState(60);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<RewriteRule | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<RewriteRule | null>(null);
  const config = status.data?.rewrite;
  const configKey = JSON.stringify(config ?? null);

  useEffect(() => {
    if (!config) return;
    setEnabled(config.enabled);
    setTtl(config.ttl);
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(
    () => Boolean(config) && (enabled !== config?.enabled || ttl !== config?.ttl),
    [config, enabled, ttl],
  );

  const save = useMutation({
    mutationFn: () => api.configureRewrite({ enabled, ttl }),
    onSuccess: () => {
      toast.success("域名重写配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
      void queryClient.invalidateQueries({ queryKey: ["rewrite-rules"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const submitRule = useMutation({
    mutationFn: async (rule: RewriteRule) => {
      await api.addRewriteRule(rule);
      if (editing && editing.domain !== rule.domain) {
        await api.deleteRewriteRule(editing.domain);
      }
    },
    onSuccess: () => {
      toast.success(editing ? "重写规则已更新" : "重写规则已添加");
      setDialogOpen(false);
      setEditing(null);
      void queryClient.invalidateQueries({ queryKey: ["rewrite-rules"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const remove = useMutation({
    mutationFn: (domain: string) => api.deleteRewriteRule(domain),
    onSuccess: () => {
      toast.success("重写规则已删除");
      setDeleteTarget(null);
      void queryClient.invalidateQueries({ queryKey: ["rewrite-rules"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => {
      setDeleteTarget(null);
      toast.error(describeError(error));
    },
  });

  const list = rules.data ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="域名重写"
        description="把指定域名直接改写为地址、CNAME、TXT 或自定义记录，不经过上游。"
        actions={
          <Button
            size="sm"
            variant="secondary"
            onClick={() => {
              setEditing(null);
              setDialogOpen(true);
            }}
          >
            <Plus className="h-3.5 w-3.5" />
            添加规则
          </Button>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading ? (
          <LoadingState label="正在加载重写配置…" />
        ) : (
          <>
            <SwitchRow
              title="启用域名重写"
              description="关闭后所有重写规则暂停，域名恢复向上游解析"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="grid gap-3 border-b border-border/60 py-2.5 sm:grid-cols-2">
              <Field label="默认 TTL（秒）" hint="规则未单独指定时使用">
                <Input
                  type="number"
                  min={1}
                  max={86400}
                  value={ttl}
                  onChange={(event) => setTtl(Number(event.target.value))}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                共 {list.length} 条规则，匹配按域名精确查找；启用中的规则会立即生效。
              </div>
            </div>

            <div className="mt-2 min-h-0 flex-1">
              {rules.isLoading ? (
                <LoadingState label="正在加载重写规则…" className="min-h-[140px]" />
              ) : list.length === 0 ? (
                <EmptyState
                  icon={Waypoints}
                  title="还没有重写规则"
                  description="添加后，指定域名的解析结果会由本机直接生成。"
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
                      添加规则
                    </Button>
                  }
                />
              ) : (
                <div className="max-h-[360px] divide-y divide-border/70 overflow-y-auto pr-1">
                  {list.map((rule) => (
                    <div key={rule.domain} className="flex items-start gap-3 py-2.5">
                      <span className="mt-1.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg bg-surface-3 text-text-3">
                        <Edit3 className="h-3 w-3" />
                      </span>
                      <div className="min-w-0 flex-1">
                        <div className="mono truncate text-[12px] text-text" title={rule.domain}>
                          {rule.domain}
                        </div>
                        <div className="mt-1 flex flex-wrap gap-1">
                          {ruleTags(rule).map((tag) => (
                            <Badge key={tag.label} tone={tag.tone}>
                              {tag.label}
                            </Badge>
                          ))}
                        </div>
                        {rule.ips && rule.ips.length > 0 ? (
                          <div className="mono mt-1 truncate text-[10px] text-text-3">
                            {rule.ips.join(", ")}
                          </div>
                        ) : rule.cname ? (
                          <div className="mono mt-1 truncate text-[10px] text-text-3">
                            → {rule.cname}
                          </div>
                        ) : null}
                      </div>
                      <div className="flex shrink-0 items-center gap-0.5">
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={`编辑 ${rule.domain}`}
                          onClick={() => {
                            setEditing(rule);
                            setDialogOpen(true);
                          }}
                        >
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          aria-label={`删除 ${rule.domain}`}
                          onClick={() => setDeleteTarget(rule)}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
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

      <RewriteRuleDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open);
          if (!open) setEditing(null);
        }}
        initial={editing}
        loading={submitRule.isPending}
        onSubmit={(rule) => submitRule.mutate(rule)}
      />

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="删除重写规则"
        description={`确定删除「${deleteTarget?.domain ?? ""}」的重写规则吗？`}
        confirmLabel="删除"
        loading={remove.isPending}
        onConfirm={() => deleteTarget && remove.mutate(deleteTarget.domain)}
      />
    </Card>
  );
}
