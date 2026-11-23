import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { FileKey2, RefreshCw, Upload } from "lucide-react";
import { toast } from "sonner";

import { useEncryptedStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber } from "../../lib/format";
import { parseList } from "../../lib/strings";
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
import { Field, Textarea } from "../ui/field";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { LoadingState } from "../ui/loading";
import { SwitchRow } from "../ui/switch-row";

const keyTypeOptions = [
  { value: "ecdsa", label: "ECDSA（推荐）" },
  { value: "rsa", label: "RSA" },
];

const importModes = [
  { value: "pem", label: "PEM 证书与私钥" },
  { value: "pkcs12", label: "PKCS#12 容器" },
];

async function fileToBase64(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunk));
  }
  return btoa(binary);
}

function GenerateDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const status = useEncryptedStatus();
  const queryClient = useQueryClient();
  const [keyType, setKeyType] = useState("ecdsa");
  const [commonName, setCommonName] = useState("dns.lan");
  const [dnsNames, setDnsNames] = useState("");
  const [ipAddresses, setIpAddresses] = useState("");
  const [validDays, setValidDays] = useState(825);
  const [force, setForce] = useState(false);
  const certConfigKey = status.data ? JSON.stringify(status.data.config.cert) : null;

  useEffect(() => {
    if (!open || !status.data) return;
    setKeyType(status.data.config.cert.keyType || "ecdsa");
    setCommonName(status.data.config.cert.commonName || status.data.config.serverName || "dns.lan");
    setDnsNames(status.data.config.cert.dnsNames.join("\n"));
    setIpAddresses(status.data.config.cert.ipAddresses.join("\n"));
    setValidDays(status.data.config.cert.validDays || 825);
    setForce(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, certConfigKey]);

  const mutate = useMutation({
    mutationFn: () =>
      api.generateEncryptedCert({
        keyType,
        commonName,
        dnsNames: parseList(dnsNames),
        ipAddresses: parseList(ipAddresses),
        validDays,
        force,
      }),
    onSuccess: () => {
      toast.success(force ? "已重新签发证书" : "证书已就绪");
      void queryClient.invalidateQueries({ queryKey: ["encrypted-status"] });
      onOpenChange(false);
    },
    onError: (error) => toast.error(describeError(error)),
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(560px,calc(100vw-40px))]">
        <DialogHeader
          title="生成自签证书"
          description="证书将用于 DoT / DoH。未填写 SAN 时按服务器名与监听地址自动推导。"
        />
        <DialogBody className="space-y-3.5">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="密钥类型">
              <Select value={keyType} options={keyTypeOptions} onValueChange={setKeyType} />
            </Field>
            <Field label="有效期（天）" hint="1 – 3650">
              <Input
                type="number"
                min={1}
                max={3650}
                value={validDays}
                onChange={(event) => setValidDays(Number(event.target.value))}
              />
            </Field>
          </div>
          <Field label="通用名（CN）">
            <Input
              className="mono"
              value={commonName}
              onChange={(event) => setCommonName(event.target.value)}
            />
          </Field>
          <Field label="DNS 名称" hint="每行一个，例如 dns.lan；留空则自动推导">
            <Textarea
              className="mono min-h-[64px] text-[11.5px]"
              value={dnsNames}
              onChange={(event) => setDnsNames(event.target.value)}
            />
          </Field>
          <Field label="IP 地址" hint="每行一个，例如 192.168.1.10">
            <Textarea
              className="mono min-h-[64px] text-[11.5px]"
              value={ipAddresses}
              onChange={(event) => setIpAddresses(event.target.value)}
            />
          </Field>
          <SwitchRow
            title="强制重新签发"
            description="已有证书时覆盖原文件，需重新在客户端信任"
            checked={force}
            onCheckedChange={setForce}
          />
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button
            variant="primary"
            loading={mutate.isPending}
            disabled={!commonName.trim() || validDays < 1 || validDays > 3650}
            onClick={() => mutate.mutate()}
          >
            生成
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ImportDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const queryClient = useQueryClient();
  const [mode, setMode] = useState<"pem" | "pkcs12">("pem");
  const [certPem, setCertPem] = useState("");
  const [keyPem, setKeyPem] = useState("");
  const [certName, setCertName] = useState("");
  const [keyName, setKeyName] = useState("");
  const [data, setData] = useState("");
  const [dataName, setDataName] = useState("");
  const [password, setPassword] = useState("");

  useEffect(() => {
    if (!open) return;
    setMode("pem");
    setCertPem("");
    setKeyPem("");
    setCertName("");
    setKeyName("");
    setData("");
    setDataName("");
    setPassword("");
  }, [open]);

  const mutate = useMutation({
    mutationFn: () =>
      api.importEncryptedCert(
        mode === "pem"
          ? { mode, certPem, keyPem }
          : { mode, data, password },
      ),
    onSuccess: () => {
      toast.success("证书已导入");
      void queryClient.invalidateQueries({ queryKey: ["encrypted-status"] });
      onOpenChange(false);
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const valid =
    mode === "pem" ? certPem.length > 0 && keyPem.length > 0 : data.length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(560px,calc(100vw-40px))]">
        <DialogHeader
          title="导入证书"
          description="文件仅在浏览器内读取后提交给本机服务，不会上传到外部。"
        />
        <DialogBody className="space-y-3.5">
          <Field label="导入方式">
            <Select
              value={mode}
              options={importModes}
              onValueChange={(value) => setMode(value as "pem" | "pkcs12")}
            />
          </Field>

          {mode === "pem" ? (
            <>
              <Field label="证书链（PEM）" hint={certName || "选择 .pem / .crt 文件"}>
                <Input
                  type="file"
                  accept=".pem,.crt,.cer,text/plain"
                  onChange={async (event) => {
                    const file = event.target.files?.[0];
                    if (!file) return;
                    setCertPem(await file.text());
                    setCertName(file.name);
                  }}
                />
              </Field>
              <Field label="私钥（PEM）" hint={keyName || "选择 .pem / .key 文件"}>
                <Input
                  type="file"
                  accept=".pem,.key,text/plain"
                  onChange={async (event) => {
                    const file = event.target.files?.[0];
                    if (!file) return;
                    setKeyPem(await file.text());
                    setKeyName(file.name);
                  }}
                />
              </Field>
            </>
          ) : (
            <>
              <Field label="PKCS#12 文件" hint={dataName || "选择 .p12 / .pfx 文件"}>
                <Input
                  type="file"
                  accept=".p12,.pfx,application/x-pkcs12"
                  onChange={async (event) => {
                    const file = event.target.files?.[0];
                    if (!file) return;
                    setData(await fileToBase64(file));
                    setDataName(file.name);
                  }}
                />
              </Field>
              <Field label="容器密码" hint="没有密码时留空">
                <Input
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                />
              </Field>
            </>
          )}
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button variant="primary" loading={mutate.isPending} disabled={!valid} onClick={() => mutate.mutate()}>
            导入
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function CertCard() {
  const status = useEncryptedStatus();
  const [generateOpen, setGenerateOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const cert = status.data?.cert;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="服务证书"
        description="DoT 与 DoH 共用同一张证书。"
        actions={
          <>
            <Button size="sm" variant="ghost" onClick={() => setImportOpen(true)}>
              <Upload className="h-3.5 w-3.5" />
              导入
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setGenerateOpen(true)}>
              <RefreshCw className="h-3.5 w-3.5" />
              签发
            </Button>
          </>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-2">
        {status.isLoading ? (
          <LoadingState label="正在加载证书状态…" />
        ) : cert ? (
          <>
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={cert.loaded ? "good" : "danger"} dot>
                {cert.loaded ? "已加载" : "未加载"}
              </Badge>
              {cert.selfSigned ? <Badge tone="violet">自签</Badge> : null}
              <Badge
                tone={
                  status.data?.certExpired
                    ? "danger"
                    : status.data?.certExpiresSoon
                      ? "warn"
                      : "neutral"
                }
              >
                {status.data?.certExpired
                  ? "已过期"
                  : `剩余 ${formatNumber(cert.daysRemaining)} 天`}
              </Badge>
              <Badge tone="neutral">{cert.source}</Badge>
            </div>

            {cert.error ? (
              <p className="mt-2 rounded-lg bg-danger-soft px-3 py-2 text-[11px] text-danger">
                {cert.error}
              </p>
            ) : null}

            <div className="mt-3 space-y-1.5 text-[11.5px]">
              <div className="flex items-start justify-between gap-4 border-b border-border/60 py-1.5">
                <span className="shrink-0 text-text-3">主题</span>
                <span className="mono break-all text-right text-text-2">{cert.subject || "—"}</span>
              </div>
              <div className="flex items-start justify-between gap-4 border-b border-border/60 py-1.5">
                <span className="shrink-0 text-text-3">签发者</span>
                <span className="mono break-all text-right text-text-2">{cert.issuer || "—"}</span>
              </div>
              <div className="flex items-center justify-between gap-4 border-b border-border/60 py-1.5">
                <span className="text-text-3">有效期至</span>
                <span className="text-right text-text-2">{cert.notAfter || "—"}</span>
              </div>
              <div className="flex items-start justify-between gap-4 border-b border-border/60 py-1.5">
                <span className="shrink-0 text-text-3">指纹</span>
                <span className="mono break-all text-right text-[10px] text-text-3">
                  {cert.fingerprint || "—"}
                </span>
              </div>
            </div>

            <div className="mt-2 flex flex-wrap gap-1.5">
              {[...cert.dnsNames, ...cert.ipAddresses].slice(0, 10).map((name) => (
                <span
                  key={name}
                  className="mono rounded-md border border-border bg-surface-2 px-1.5 py-0.5 text-[10px] text-text-2"
                >
                  {name}
                </span>
              ))}
            </div>
          </>
        ) : (
          <p className="text-[11.5px] text-text-3">无法读取证书状态。</p>
        )}
      </CardContent>
      <CardFooter>
        <span className="flex items-center gap-1.5 text-[10.5px] text-text-3">
          <FileKey2 className="h-3 w-3" />
          证书目录
        </span>
        <span className="mono max-w-[70%] truncate text-[10px] text-text-2" title={status.data?.certDir}>
          {status.data?.certDir ?? "—"}
        </span>
      </CardFooter>

      <GenerateDialog open={generateOpen} onOpenChange={setGenerateOpen} />
      <ImportDialog open={importOpen} onOpenChange={setImportOpen} />
    </Card>
  );
}
