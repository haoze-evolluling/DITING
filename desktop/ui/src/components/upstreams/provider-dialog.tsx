import { useEffect, useState } from "react";
import { ScanLine } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import type { ProviderConfig } from "../../lib/types";
import { Field } from "../ui/field";
import { Button } from "../ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { Input } from "../ui/input";
import { Select } from "../ui/select";

const protocolOptions = [
  { value: "PLAIN", label: "UDP / TCP（传统 DNS）" },
  { value: "DOT", label: "DoT（DNS over TLS）" },
  { value: "DOH", label: "DoH（DNS over HTTPS）" },
];

const emptyProvider: ProviderConfig = {
  id: "",
  protocol: "DOT",
  server: "",
  url: "",
  weight: 1,
  pin: "",
};

export function ProviderDialog({
  open,
  onOpenChange,
  initial,
  onSubmit,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ProviderConfig | null;
  onSubmit: (provider: ProviderConfig) => void;
}) {
  const [draft, setDraft] = useState<ProviderConfig>(emptyProvider);
  const [stamp, setStamp] = useState("");
  const [parsing, setParsing] = useState(false);

  useEffect(() => {
    if (!open) return;
    setDraft(initial ? { ...emptyProvider, ...initial } : { ...emptyProvider });
    setStamp("");
  }, [open, initial]);

  const update = (patch: Partial<ProviderConfig>) =>
    setDraft((current) => ({ ...current, ...patch }));

  const parseStamp = async () => {
    if (!stamp.trim()) {
      toast.error("请先粘贴 DNS Stamp");
      return;
    }
    setParsing(true);
    try {
      const parsed = await api.parseStamp(stamp.trim());
      setDraft((current) => ({
        ...current,
        id: current.id || parsed.providerName || parsed.server || parsed.url || "新上游",
        protocol: parsed.protocol || current.protocol,
        server: parsed.server || current.server,
        url: parsed.url || current.url,
        pin: parsed.pin || current.pin,
      }));
      toast.success("已从 Stamp 解析上游信息");
    } catch (error) {
      toast.error(describeError(error));
    } finally {
      setParsing(false);
    }
  };

  const valid =
    draft.id.trim().length > 0 &&
    (draft.server.trim().length > 0 || draft.url.trim().length > 0);

  const submit = () => {
    if (!valid) {
      toast.error("请填写上游名称，并至少提供服务器地址或 DoH URL");
      return;
    }
    onSubmit({
      ...draft,
      id: draft.id.trim(),
      protocol: draft.protocol.toUpperCase(),
      server: draft.server.trim(),
      url: draft.url.trim(),
      pin: draft.pin?.trim() ?? "",
      weight: Number(draft.weight) > 0 ? Number(draft.weight) : 1,
    });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader
          title={initial ? "编辑上游" : "添加上游"}
          description="支持传统 DNS、DoT 与 DoH。名称将作为上游标识，必须唯一。"
        />
        <DialogBody className="space-y-3.5">
          <div className="rounded-xl border border-border bg-surface-2 p-3">
            <div className="flex items-center justify-between gap-2">
              <span className="flex items-center gap-1.5 text-[11.5px] text-text-2">
                <ScanLine className="h-3.5 w-3.5 text-text-3" />
                从 DNS Stamp 导入
              </span>
              <Button size="sm" variant="ghost" loading={parsing} onClick={() => void parseStamp()}>
                解析
              </Button>
            </div>
            <Input
              className="mt-2"
              value={stamp}
              placeholder="sdns://..."
              onChange={(event) => setStamp(event.target.value)}
            />
          </div>

          <Field label="名称">
            <Input
              value={draft.id}
              placeholder="例如：阿里云 (DoT)"
              onChange={(event) => update({ id: event.target.value })}
            />
          </Field>

          <Field label="协议">
            <Select
              value={draft.protocol.toUpperCase()}
              options={protocolOptions}
              onValueChange={(value) => update({ protocol: value })}
            />
          </Field>

          <Field
            label="服务器地址"
            hint={
              draft.protocol.toUpperCase() === "PLAIN"
                ? "例如 223.5.5.5:53；省略端口时默认 53"
                : "例如 dns.alidns.com:853；DoH 可留空并填写下方 URL"
            }
          >
            <Input
              value={draft.server}
              placeholder={draft.protocol.toUpperCase() === "DOH" ? "可留空" : "1.1.1.1:53"}
              onChange={(event) => update({ server: event.target.value })}
            />
          </Field>

          {draft.protocol.toUpperCase() === "DOH" ? (
            <Field label="DoH URL" hint="例如 https://dns.alidns.com/dns-query">
              <Input
                value={draft.url}
                placeholder="https://example.com/dns-query"
                onChange={(event) => update({ url: event.target.value })}
              />
            </Field>
          ) : null}

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="权重" hint="并发或智能选择时参与调度">
              <Input
                type="number"
                min={1}
                value={draft.weight ?? 1}
                onChange={(event) => update({ weight: Number(event.target.value) })}
              />
            </Field>
            <Field label="证书公钥指纹" hint="可选，用于固定 DoT/DoH 证书">
              <Input
                value={draft.pin ?? ""}
                placeholder="AA:BB:CC:..."
                onChange={(event) => update({ pin: event.target.value })}
              />
            </Field>
          </div>
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button variant="primary" onClick={submit} disabled={!valid}>
            保存上游
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
