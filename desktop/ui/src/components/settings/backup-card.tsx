import { useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Download, Upload } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import { formatDateTime } from "../../lib/format";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { ConfirmDialog } from "../ui/confirm-dialog";
import { InfoRow } from "../ui/info-row";

// 服务端请求体上限 4 MiB，JSON 字符串转义会略微放大，这里留出余量。
const MAX_BACKUP_BYTES = 3 * 1024 * 1024;
const BACKUP_FORMAT = "diting-desktop-backup";

interface BackupPreview {
  name: string;
  content: string;
  exportedAt: number;
  appVersion: string;
  sections: string[];
}

function previewBackup(name: string, text: string): BackupPreview {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("备份文件不是有效的 JSON");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("备份文件的根节点必须是 JSON 对象");
  }
  const record = parsed as Record<string, unknown>;
  if (record.format !== BACKUP_FORMAT) {
    throw new Error("所选文件不是谛听桌面端配置备份");
  }
  const data = record.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("备份文件缺少配置数据");
  }
  const sections = Object.keys(data as Record<string, unknown>);
  if (sections.length === 0) {
    throw new Error("备份文件中没有可恢复的配置");
  }
  return {
    name,
    content: text,
    exportedAt: typeof record.exportedAt === "number" ? record.exportedAt : 0,
    appVersion: typeof record.appVersion === "string" ? record.appVersion : "",
    sections,
  };
}

export function BackupCard() {
  const queryClient = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState<BackupPreview | null>(null);

  const exportBackup = useMutation({
    mutationFn: api.exportConfig,
    onSuccess: (result) => toast.success(`配置备份已导出：${result.filename}`),
    onError: (error) => toast.error(describeError(error)),
  });

  const importBackup = useMutation({
    mutationFn: (content: string) => api.importConfig(content),
    onSuccess: (result) => {
      setPending(null);
      void queryClient.invalidateQueries();
      if (result.restartWarning) {
        toast.warning(result.restartWarning);
      } else {
        toast.success(`配置已导入并生效，共恢复 ${result.sections} 项`);
      }
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const pickFile = async (file: File | undefined) => {
    if (!file) return;
    if (file.size > MAX_BACKUP_BYTES) {
      toast.error("备份文件不能超过 3MB");
      return;
    }
    try {
      const text = await file.text();
      setPending(previewBackup(file.name, text));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "读取备份文件失败");
    } finally {
      if (inputRef.current) inputRef.current.value = "";
    }
  };

  return (
    <>
      <Card className="flex flex-col">
        <CardHeader
          title="配置备份"
          description="导出可移植的业务配置，或从 JSON 备份文件恢复。"
          actions={<Badge tone="neutral">JSON</Badge>}
        />
        <CardContent className="flex-1 pt-1">
          <InfoRow label="包含内容">
            DNS、上游、缓存策略、规则订阅与自定义规则、重写、局域网、加密 DNS 与隐私策略
          </InfoRow>
          <InfoRow label="不含内容">
            管理员凭据、证书私钥、登录背景、接管状态与已下载的订阅缓存
          </InfoRow>
          <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] leading-5 text-text-3">
            导入会覆盖当前业务配置；管理员账号、管理端口与证书保持本机设置不变。若 DNS
            正在运行，导入后会自动按新配置重启监听器。迁移到新设备后，订阅规则会在下次更新时重新下载。
          </p>
        </CardContent>
        <CardFooter>
          <span className="text-[10.5px] text-text-3">
            建议在调整规则或迁移设备前导出一份备份。
          </span>
          <div className="flex items-center gap-1.5">
            <Button
              size="sm"
              variant="ghost"
              loading={exportBackup.isPending}
              onClick={() => exportBackup.mutate()}
            >
              <Download className="h-3.5 w-3.5" />
              导出
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => inputRef.current?.click()}
            >
              <Upload className="h-3.5 w-3.5" />
              导入
            </Button>
          </div>
        </CardFooter>
        <input
          ref={inputRef}
          type="file"
          accept="application/json,.json"
          className="hidden"
          onChange={(event) => void pickFile(event.target.files?.[0])}
        />
      </Card>

      <ConfirmDialog
        open={Boolean(pending)}
        onOpenChange={(open) => {
          if (!open && !importBackup.isPending) setPending(null);
        }}
        title="导入配置备份"
        confirmLabel="导入并覆盖"
        loading={importBackup.isPending}
        onConfirm={() => {
          if (pending) importBackup.mutate(pending.content);
        }}
        description={
          pending ? (
            <div className="space-y-2">
              <p>即将使用备份文件覆盖当前业务配置，此操作不可撤销。</p>
              <dl className="space-y-1 rounded-xl border border-border bg-surface-2 px-3 py-2 text-[11.5px]">
                <div className="flex justify-between gap-3">
                  <dt className="text-text-3">文件</dt>
                  <dd className="min-w-0 truncate text-text-2">{pending.name}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-text-3">导出时间</dt>
                  <dd className="num text-text-2">
                    {pending.exportedAt ? formatDateTime(pending.exportedAt) : "—"}
                  </dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-text-3">配置分节</dt>
                  <dd className="num text-text-2">{pending.sections.length} 项</dd>
                </div>
                {pending.appVersion ? (
                  <div className="flex justify-between gap-3">
                    <dt className="text-text-3">导出版本</dt>
                    <dd className="num text-text-2">v{pending.appVersion}</dd>
                  </div>
                ) : null}
              </dl>
              <p className="text-[11px] text-text-3">
                管理员凭据、证书与登录背景不会改变。
              </p>
            </div>
          ) : null
        }
      />
    </>
  );
}
