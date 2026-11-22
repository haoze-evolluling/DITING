import { useEffect, useState } from "react";

import { joinLines, parseLines } from "../../lib/strings";
import type { RewriteRecord, RewriteRule } from "../../lib/types";
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

const rcodeOptions = [
  { value: "", label: "默认（正常返回）" },
  { value: "NOERROR", label: "NOERROR" },
  { value: "NXDOMAIN", label: "NXDOMAIN" },
  { value: "REFUSED", label: "REFUSED" },
  { value: "SERVFAIL", label: "SERVFAIL" },
  { value: "NOTIMP", label: "NOTIMP" },
];

function recordsToText(records: RewriteRecord[] | undefined): string {
  return (records ?? []).map((record) => `${record.type} ${record.value}`).join("\n");
}

function parseRecords(text: string): RewriteRecord[] {
  const out: RewriteRecord[] = [];
  for (const line of parseLines(text)) {
    const [type, ...rest] = line.split(/\s+/);
    const value = rest.join(" ").trim();
    if (!type || !value) continue;
    out.push({ type: type.toUpperCase(), value });
  }
  return out;
}

export function RewriteRuleDialog({
  open,
  onOpenChange,
  initial,
  onSubmit,
  loading,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: RewriteRule | null;
  onSubmit: (rule: RewriteRule) => void;
  loading?: boolean;
}) {
  const [domain, setDomain] = useState("");
  const [ttl, setTtl] = useState("0");
  const [ips, setIps] = useState("");
  const [cname, setCname] = useState("");
  const [txt, setTxt] = useState("");
  const [records, setRecords] = useState("");
  const [rcode, setRcode] = useState("");

  useEffect(() => {
    if (!open) return;
    setDomain(initial?.domain ?? "");
    setTtl(String(initial?.ttl ?? 0));
    setIps(joinLines(initial?.ips));
    setCname(initial?.cname ?? "");
    setTxt(joinLines(initial?.txt));
    setRecords(recordsToText(initial?.records));
    setRcode(initial?.rcode ?? "");
  }, [open, initial]);

  const ipList = parseLines(ips);
  const txtList = parseLines(txt);
  const recordList = parseRecords(records);
  const valid =
    domain.trim().length > 0 &&
    (ipList.length > 0 ||
      cname.trim().length > 0 ||
      txtList.length > 0 ||
      recordList.length > 0 ||
      rcode.length > 0);

  const submit = () => {
    const rule: RewriteRule = { domain: domain.trim().replace(/\.$/, "") };
    if (ipList.length > 0) rule.ips = ipList;
    if (cname.trim()) rule.cname = cname.trim().replace(/\.$/, "");
    if (txtList.length > 0) rule.txt = txtList;
    if (recordList.length > 0) rule.records = recordList;
    if (rcode) rule.rcode = rcode;
    const ttlValue = Number(ttl);
    if (Number.isFinite(ttlValue) && ttlValue > 0) rule.ttl = ttlValue;
    onSubmit(rule);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(600px,calc(100vw-40px))]">
        <DialogHeader
          title={initial ? "编辑重写规则" : "添加重写规则"}
          description="同一域名可同时配置地址、CNAME、TXT 与自定义记录；规则按域名唯一。"
        />
        <DialogBody className="space-y-3.5">
          <div className="grid gap-3 sm:grid-cols-[1.4fr_1fr]">
            <Field label="域名" hint="填写后自动去除末尾的点">
              <Input
                className="mono"
                value={domain}
                placeholder="例如：nas.home.lan"
                onChange={(event) => setDomain(event.target.value)}
              />
            </Field>
            <Field label="TTL（秒）" hint="0 表示使用全局默认 TTL">
              <Input
                type="number"
                min={0}
                max={86400}
                value={ttl}
                onChange={(event) => setTtl(event.target.value)}
              />
            </Field>
          </div>

          <Field label="IP 地址" hint="每行一个 IPv4 或 IPv6 地址">
            <Textarea
              className="mono min-h-[72px] text-[11.5px]"
              value={ips}
              spellCheck={false}
              placeholder={"192.168.1.10\nfe80::1"}
              onChange={(event) => setIps(event.target.value)}
            />
          </Field>

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="CNAME">
              <Input
                className="mono"
                value={cname}
                placeholder="target.example.com"
                onChange={(event) => setCname(event.target.value)}
              />
            </Field>
            <Field label="RCODE" hint="强制返回指定响应码">
              <Select
                value={rcode}
                options={rcodeOptions}
                onValueChange={setRcode}
                ariaLabel="响应码"
              />
            </Field>
          </div>

          <Field label="TXT 记录" hint="每行一条 TXT 内容">
            <Textarea
              className="mono min-h-[64px] text-[11.5px]"
              value={txt}
              spellCheck={false}
              placeholder="v=spf1 -all"
              onChange={(event) => setTxt(event.target.value)}
            />
          </Field>

          <Field label="自定义记录" hint="每行 `TYPE VALUE`，例如 `MX 10 mail.example.com`">
            <Textarea
              className="mono min-h-[64px] text-[11.5px]"
              value={records}
              spellCheck={false}
              placeholder={"MX 10 mail.example.com\nSRV 0 5 443 target.example.com"}
              onChange={(event) => setRecords(event.target.value)}
            />
          </Field>
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button variant="primary" disabled={!valid} loading={loading} onClick={submit}>
            保存规则
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
