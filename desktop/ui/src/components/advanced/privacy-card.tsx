import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ShieldEllipsis } from "lucide-react";
import { toast } from "sonner";

import { useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { SwitchRowsSkeleton } from "../skeletons/parts";
import { SwitchRow } from "../ui/switch-row";

const anyModeOptions = [
  { value: "notimp", label: "返回 NOTIMP" },
  { value: "rfc8482", label: "RFC 8482 HINFO" },
];

interface PrivacyDraft {
  enableEDE: boolean;
  blockPrivatePTR: boolean;
  blockIPv6: boolean;
  blockECH: boolean;
  ednsPadding: number;
  blockANY: boolean;
  blockANYMode: string;
  blockUnqualified: boolean;
}

export function PrivacyCard() {
  const status = useStatus();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<PrivacyDraft | null>(null);
  const dns = status.data?.dns;
  const configKey = JSON.stringify(
    dns
      ? {
          enableEDE: dns.enableEDE,
          blockPrivatePTR: dns.blockPrivatePTR,
          blockIPv6: dns.blockIPv6,
          blockECH: dns.blockECH,
          ednsPadding: dns.ednsPadding,
          blockANY: dns.blockANY,
          blockANYMode: dns.blockANYMode,
          blockUnqualified: dns.blockUnqualified,
        }
      : null,
  );

  useEffect(() => {
    if (!dns) return;
    setDraft({
      enableEDE: dns.enableEDE,
      blockPrivatePTR: dns.blockPrivatePTR,
      blockIPv6: dns.blockIPv6,
      blockECH: dns.blockECH,
      ednsPadding: dns.ednsPadding,
      blockANY: dns.blockANY,
      blockANYMode: dns.blockANYMode,
      blockUnqualified: dns.blockUnqualified,
    });
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configKey]);

  const dirty = useMemo(() => {
    if (!dns || !draft) return false;
    return JSON.stringify(draft) !== JSON.stringify(JSON.parse(configKey) as PrivacyDraft);
  }, [dns, draft, configKey]);

  const save = useMutation({
    mutationFn: async () => {
      if (!draft) throw new Error("配置尚未加载");
      await api.configurePrivacy({
        enableEDE: draft.enableEDE,
        blockPrivatePTR: draft.blockPrivatePTR,
        blockIPv6: draft.blockIPv6,
        blockECH: draft.blockECH,
        ednsPadding: draft.ednsPadding,
        blockANY: draft.blockANY,
        blockANYMode: draft.blockANYMode,
      });
      await api.configureUnqualified(draft.blockUnqualified);
    },
    onSuccess: () => {
      toast.success("DNS 隐私与协议加固配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<PrivacyDraft>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const valid = draft && draft.ednsPadding >= 0 && draft.ednsPadding <= 4096;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="隐私与协议加固"
        description="控制响应细节、敏感记录与协议降级行为。"
        actions={<ShieldEllipsis className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {status.isLoading || !draft ? (
          <SwitchRowsSkeleton rows={4} />
        ) : (
          <>
            <SwitchRow
              title="扩展 DNS 错误（EDE）"
              description="在拦截应答中附带错误原因"
              checked={draft.enableEDE}
              onCheckedChange={(enableEDE) => update({ enableEDE })}
            />
            <SwitchRow
              title="阻断私有 PTR 查询"
              description="阻止内网地址反向解析泄露到上游"
              checked={draft.blockPrivatePTR}
              onCheckedChange={(blockPrivatePTR) => update({ blockPrivatePTR })}
            />
            <SwitchRow
              title="阻断 AAAA / IPv6"
              description="强制只返回 IPv4 结果"
              checked={draft.blockIPv6}
              onCheckedChange={(blockIPv6) => update({ blockIPv6 })}
            />
            <SwitchRow
              title="阻断 HTTPS / ECH"
              description="拦截 HTTPS 与 SVCB 记录，避免 ECH 绕过过滤"
              checked={draft.blockECH}
              onCheckedChange={(blockECH) => update({ blockECH })}
            />
            <SwitchRow
              title="阻断 ANY 查询"
              description="拒绝 ANY 类型查询，降低放大风险"
              checked={draft.blockANY}
              onCheckedChange={(blockANY) => update({ blockANY })}
            />
            {draft.blockANY ? (
              <div className="grid gap-3 border-b border-border/60 py-2.5 sm:grid-cols-2">
                <Field label="ANY 响应方式">
                  <Select
                    value={draft.blockANYMode}
                    options={anyModeOptions}
                    onValueChange={(blockANYMode) => update({ blockANYMode })}
                    ariaLabel="ANY 响应方式"
                  />
                </Field>
              </div>
            ) : null}
            <SwitchRow
              title="阻断单标签域名"
              description="拒绝无点的内网主机名外泄到上游"
              checked={draft.blockUnqualified}
              onCheckedChange={(blockUnqualified) => update({ blockUnqualified })}
            />
            <div className="grid gap-3 pt-2.5 sm:grid-cols-2">
              <Field label="EDNS 填充长度" hint="0 表示禁用，常用 128 字节">
                <Input
                  type="number"
                  min={0}
                  max={4096}
                  value={draft.ednsPadding}
                  onChange={(event) => update({ ednsPadding: Number(event.target.value) })}
                />
              </Field>
              <div className="flex items-end pb-1 text-[10.5px] leading-4 text-text-3">
                填充可降低报文长度泄露；过大会增加流量开销。
              </div>
            </div>
            {!valid ? (
              <p className="mt-2 rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                EDNS 填充长度需在 0 – 4096 之间。
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
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}
