import { Copy } from "lucide-react";
import type { ReactNode } from "react";
import { toast } from "sonner";

import { displayDomain, formatDateTime, formatLatency } from "../../lib/format";
import { cacheHitLabel } from "../../lib/labels";
import type { QueryRecord } from "../../lib/types";
import { Button } from "../ui/button";
import { Sheet } from "../ui/sheet";
import { StatusBadge } from "../ui/status-badge";

function Row({ label, children, mono = false }: { label: string; children: ReactNode; mono?: boolean }) {
  return (
    <div className="grid grid-cols-[92px_1fr] gap-3 border-b border-border/60 py-2 last:border-b-0">
      <span className="text-[11.5px] text-text-3">{label}</span>
      <span className={mono ? "mono break-all text-[11.5px] text-text-2" : "text-[12px] text-text"}>
        {children}
      </span>
    </div>
  );
}

export function QueryDetailSheet({
  record,
  open,
  onOpenChange,
}: {
  record: QueryRecord | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const copyDomain = async () => {
    if (!record) return;
    try {
      await navigator.clipboard.writeText(record.domain);
      toast.success("域名已复制");
    } catch {
      toast.error("无法访问剪贴板");
    }
  };

  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title={record ? displayDomain(record.domain) : "查询详情"}
      description={record ? formatDateTime(record.ts) : undefined}
      footer={
        <div className="flex justify-end gap-2">
          <Button size="sm" variant="ghost" onClick={() => void copyDomain()}>
            <Copy className="h-3.5 w-3.5" />
            复制域名
          </Button>
          <Button size="sm" variant="primary" onClick={() => onOpenChange(false)}>
            关闭
          </Button>
        </div>
      }
    >
      {record ? (
        <div>
          <div className="mb-4 flex items-center gap-2">
            <StatusBadge status={record.status} />
            <span className="text-[11.5px] text-text-3">{record.qtype || "未知类型"}</span>
          </div>
          <Row label="域名" mono>
            {displayDomain(record.domain)}
          </Row>
          <Row label="时间">{formatDateTime(record.ts)}</Row>
          <Row label="客户端">
            {record.clientName ? `${record.clientName} · ` : ""}
            <span className="mono">{record.clientIP || "未知"}</span>
          </Row>
          <Row label="解析耗时">{formatLatency(record.durationMs)}</Row>
          <Row label="响应码">{record.rcode || "—"}</Row>
          <Row label="传输协议">{record.protocol || "—"}</Row>
          <Row label="缓存标识">
            {record.cacheHit ? cacheHitLabel(record.cacheHit) : record.cached ? "命中" : "未命中"}
          </Row>
          <Row label="TTL">{record.ttl ?? "—"}</Row>
          <Row label="上游">{record.upstreamProvider || "—"}</Row>
          {record.filterRule ? (
            <div className="mt-3">
              <div className="mb-1.5 text-[11.5px] text-text-3">匹配规则</div>
              <pre className="mono overflow-x-auto rounded-lg border border-border bg-surface-2 px-3 py-2 text-[11px] text-text-2">
                {record.filterRule}
              </pre>
            </div>
          ) : null}
          {record.filterReason ? (
            <div className="mt-3">
              <div className="mb-1.5 text-[11.5px] text-text-3">拦截原因</div>
              <p className="rounded-lg bg-danger-soft px-3 py-2 text-[11.5px] leading-5 text-danger">
                {record.filterReason}
              </p>
            </div>
          ) : null}
          {record.error ? (
            <div className="mt-3">
              <div className="mb-1.5 text-[11.5px] text-text-3">错误信息</div>
              <p className="rounded-lg bg-danger-soft px-3 py-2 text-[11.5px] leading-5 text-danger">
                {record.error}
              </p>
            </div>
          ) : null}
        </div>
      ) : null}
    </Sheet>
  );
}
