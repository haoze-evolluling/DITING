import { useEffect, useState } from "react";

import { cn } from "../../lib/cn";
import { joinLines, parseLines } from "../../lib/strings";
import type {
  ClientGroup,
  ClientGroupRuleListOption,
  ClientGroupUpstreamOption,
} from "../../lib/types";
import { Button } from "../ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { SwitchRow } from "../ui/switch-row";

const blockModeOptions = [
  { value: "", label: "继承全局拦截方式" },
  { value: "null_ip", label: "返回空地址" },
  { value: "nxdomain", label: "NXDOMAIN" },
  { value: "refused", label: "REFUSED" },
];

function toggle(set: Set<string>, id: string): Set<string> {
  const next = new Set(set);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}

export function ClientGroupDialog({
  open,
  onOpenChange,
  initial,
  ruleLists,
  upstreams,
  onSubmit,
  loading,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ClientGroup | null;
  ruleLists: ClientGroupRuleListOption[];
  upstreams: ClientGroupUpstreamOption[];
  onSubmit: (group: ClientGroup) => void;
  loading?: boolean;
}) {
  const [name, setName] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [clients, setClients] = useState("");
  const [ruleListIds, setRuleListIds] = useState<Set<string>>(new Set());
  const [upstreamIds, setUpstreamIds] = useState<Set<string>>(new Set());
  const [blockMode, setBlockMode] = useState("");
  const [allowlistOnly, setAllowlistOnly] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(initial?.name ?? "");
    setEnabled(initial?.enabled ?? true);
    setClients(joinLines(initial?.clients));
    setRuleListIds(new Set(initial?.ruleListIds ?? []));
    setUpstreamIds(new Set(initial?.upstreamIds ?? []));
    setBlockMode(initial?.blockMode ?? "");
    setAllowlistOnly(initial?.allowlistOnly ?? false);
  }, [open, initial]);

  const members = parseLines(clients);
  const valid = name.trim().length > 0 && members.length > 0;

  const submit = () => {
    onSubmit({
      ...(initial ?? {}),
      id: initial?.id ?? "",
      name: name.trim(),
      enabled,
      clients: members,
      ruleListIds: [...ruleListIds],
      upstreamIds: [...upstreamIds],
      blockMode,
      allowlistOnly,
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(620px,calc(100vw-40px))]">
        <DialogHeader
          title={initial ? "编辑客户端分组" : "添加客户端分组"}
          description="为指定客户端覆盖订阅源、上游与拦截方式，实现按人群的差异化策略。"
        />
        <DialogBody className="space-y-3.5">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="分组名称">
              <Input
                value={name}
                placeholder="例如：儿童设备"
                onChange={(event) => setName(event.target.value)}
              />
            </Field>
            <Field label="拦截方式" hint="留空继承全局设置">
              <Select
                value={blockMode}
                options={blockModeOptions}
                onValueChange={setBlockMode}
                ariaLabel="分组拦截方式"
              />
            </Field>
          </div>

          <Field
            label="成员客户端"
            hint="每行一个 IP 或 CIDR 网段，成员不能重复出现在其他分组。"
          >
            <Textarea
              className="mono min-h-[92px] text-[11.5px]"
              value={clients}
              spellCheck={false}
              placeholder={"192.168.1.20\n192.168.1.100/32"}
              onChange={(event) => setClients(event.target.value)}
            />
          </Field>

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <span className="text-[12px] text-text">规则订阅</span>
              <div className="mt-1.5 flex min-h-[64px] flex-wrap gap-1.5 rounded-lg border border-border bg-surface-2 p-2">
                {ruleLists.length === 0 ? (
                  <span className="self-center text-[10.5px] text-text-3">暂无订阅源</span>
                ) : (
                  ruleLists.map((list) => {
                    const active = ruleListIds.has(list.id);
                    return (
                      <button
                        key={list.id}
                        type="button"
                        aria-pressed={active}
                        onClick={() => setRuleListIds((current) => toggle(current, list.id))}
                        className={cn(
                          "rounded-lg border px-2 py-1 text-[11px] transition-colors",
                          active
                            ? "border-accent/25 bg-accent-soft text-accent"
                            : "border-border bg-surface text-text-2 hover:bg-surface-3",
                        )}
                      >
                        {list.name}
                      </button>
                    );
                  })
                )}
              </div>
              <span className="mt-1 block text-[10.5px] text-text-3">
                未选择时沿用全局订阅源
              </span>
            </div>

            <div>
              <span className="text-[12px] text-text">上游服务器</span>
              <div className="mt-1.5 flex min-h-[64px] flex-wrap gap-1.5 rounded-lg border border-border bg-surface-2 p-2">
                {upstreams.length === 0 ? (
                  <span className="self-center text-[10.5px] text-text-3">暂无上游</span>
                ) : (
                  upstreams.map((upstream) => {
                    const active = upstreamIds.has(upstream.id);
                    return (
                      <button
                        key={upstream.id}
                        type="button"
                        title={`${upstream.protocol} ${upstream.server}`}
                        aria-pressed={active}
                        onClick={() => setUpstreamIds((current) => toggle(current, upstream.id))}
                        className={cn(
                          "rounded-lg border px-2 py-1 text-[11px] transition-colors",
                          active
                            ? "border-accent/25 bg-accent-soft text-accent"
                            : "border-border bg-surface text-text-2 hover:bg-surface-3",
                        )}
                      >
                        {upstream.id}
                      </button>
                    );
                  })
                )}
              </div>
              <span className="mt-1 block text-[10.5px] text-text-3">
                未选择时沿用全局上游
              </span>
            </div>
          </div>

          <SwitchRow
            title="启用该分组"
            description="停用后成员回退到全局策略"
            checked={enabled}
            onCheckedChange={setEnabled}
          />
          <SwitchRow
            title="仅使用白名单"
            description="只放行全局白名单命中的域名"
            checked={allowlistOnly}
            onCheckedChange={setAllowlistOnly}
          />
          {initial?.schedules && initial.schedules.length > 0 ? (
            <p className="rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] text-text-3">
              该分组已有 {initial.schedules.length} 个时间计划，保存时会保留原有计划。
            </p>
          ) : null}
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button variant="primary" disabled={!valid} loading={loading} onClick={submit}>
            保存分组
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
