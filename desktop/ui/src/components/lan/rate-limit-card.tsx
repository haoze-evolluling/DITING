import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Gauge, Save } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { joinLines, parseLines } from "../../lib/strings";
import type { RateLimitConfig } from "../../lib/types";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { FieldGridSkeleton, SwitchRowsSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

export function RateLimitCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<RateLimitConfig | null>(null);
  const [exempt, setExempt] = useState("");
  const rateLimitKey = JSON.stringify(status.data?.rateLimit ?? null);

  useEffect(() => {
    if (!status.data?.rateLimit) return;
    setDraft({ ...status.data.rateLimit, exemptIPs: [...status.data.rateLimit.exemptIPs] });
    setExempt(joinLines(status.data.rateLimit.exemptIPs));
    // 仅在服务端配置实际变化时重置草稿，避免状态轮询覆盖正在编辑的内容。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rateLimitKey]);

  const exemptList = useMemo(() => parseLines(exempt), [exempt]);
  const dirty = useMemo(() => {
    const source = status.data?.rateLimit;
    if (!source || !draft) return false;
    return (
      JSON.stringify({ ...draft, exemptIPs: exemptList }) !==
      JSON.stringify({ ...source, exemptIPs: source.exemptIPs })
    );
  }, [status.data?.rateLimit, draft, exemptList]);

  const save = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("配置尚未加载");
      return api.configureRateLimit({ ...draft, exemptIPs: exemptList });
    },
    onSuccess: () => {
      toast.success("客户端速率限制已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<RateLimitConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const valid =
    draft &&
    draft.rate > 0 &&
    draft.burst >= 1 &&
    draft.ipv4Prefix >= 0 &&
    draft.ipv4Prefix <= 32 &&
    draft.ipv6Prefix >= 0 &&
    draft.ipv6Prefix <= 128;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="客户端速率限制"
        description="按来源 IP 或网段限制查询速率，抑制异常刷量与放大攻击。"
        actions={<Gauge className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading || !draft ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={2} />
            <FieldGridSkeleton fields={2} />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用速率限制"
              description="超出令牌桶容量的查询会返回拒绝应答"
              checked={draft.enabled}
              onCheckedChange={(enabled) => update({ enabled })}
            />
            <div className="mt-2 grid grid-cols-2 gap-3">
              <Field label="每秒查询数" hint="单个来源允许的稳定速率">
                <Input
                  type="number"
                  min={0.1}
                  step={0.1}
                  value={draft.rate}
                  onChange={(event) => update({ rate: Number(event.target.value) })}
                />
              </Field>
              <Field label="突发容量" hint="允许瞬时超过速率的请求数">
                <Input
                  type="number"
                  min={1}
                  value={draft.burst}
                  onChange={(event) => update({ burst: Number(event.target.value) })}
                />
              </Field>
              <Field label="IPv4 聚合前缀" hint="0 – 32，按网段共享令牌桶">
                <Input
                  type="number"
                  min={0}
                  max={32}
                  value={draft.ipv4Prefix}
                  onChange={(event) => update({ ipv4Prefix: Number(event.target.value) })}
                />
              </Field>
              <Field label="IPv6 聚合前缀" hint="0 – 128，按网段共享令牌桶">
                <Input
                  type="number"
                  min={0}
                  max={128}
                  value={draft.ipv6Prefix}
                  onChange={(event) => update({ ipv6Prefix: Number(event.target.value) })}
                />
              </Field>
            </div>
            <Field label="豁免地址" hint="每行一个 IP 或网段，不受速率限制">
              <Textarea
                className="mono min-h-[72px] text-[11.5px]"
                value={exempt}
                spellCheck={false}
                placeholder={"127.0.0.1\n::1\n192.168.1.0/24"}
                onChange={(event) => setExempt(event.target.value)}
              />
            </Field>
            {!valid ? (
              <p className="rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                速率需大于 0，突发容量至少为 1，前缀长度需在允许范围内。
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
