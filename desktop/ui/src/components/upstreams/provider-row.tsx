import { FlaskConical, Pencil, Trash2 } from "lucide-react";

import { cn } from "../../lib/cn";
import { formatLatency } from "../../lib/format";
import { protocolLabel } from "../../lib/labels";
import type { ProviderConfig, UpstreamTestResult } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";

export interface TestState {
  loading: boolean;
  result?: UpstreamTestResult;
  error?: string;
}

export function ProviderRow({
  provider,
  test,
  onTest,
  onEdit,
  onDelete,
}: {
  provider: ProviderConfig;
  test?: TestState;
  onTest: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="flex items-start gap-3 py-3">
      <span
        className={cn(
          "mt-2 h-1.5 w-1.5 shrink-0 rounded-full",
          test?.loading
            ? "animate-pulse bg-warn"
            : test?.result?.success
              ? "bg-good"
              : test?.result || test?.error
                ? "bg-danger"
                : "bg-text-3",
        )}
      />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <span className="truncate text-[12.5px] font-medium text-text">{provider.id}</span>
          <Badge tone="neutral">{protocolLabel(provider.protocol)}</Badge>
          {(provider.weight ?? 1) > 1 ? <Badge tone="accent">权重 {provider.weight}</Badge> : null}
          {provider.pin ? <Badge tone="violet">指纹固定</Badge> : null}
        </div>
        <div className="mono mt-1 truncate text-[10.5px] text-text-3">
          {provider.server || provider.url || "—"}
        </div>
        {test && !test.loading ? (
          <div
            className={cn(
              "mt-1 text-[10.5px]",
              test.result?.success ? "text-good" : "text-danger",
            )}
          >
            {test.result?.success
              ? `连接正常 · ${formatLatency(test.result.latencyMs)}`
              : test.error ?? test.result?.error ?? "连接失败"}
          </div>
        ) : null}
      </div>
      <div className="flex shrink-0 items-center gap-0.5">
        <Button
          size="icon"
          variant="ghost"
          aria-label={`测试 ${provider.id}`}
          loading={test?.loading}
          onClick={onTest}
        >
          <FlaskConical className="h-3.5 w-3.5" />
        </Button>
        <Button size="icon" variant="ghost" aria-label={`编辑 ${provider.id}`} onClick={onEdit}>
          <Pencil className="h-3.5 w-3.5" />
        </Button>
        <Button size="icon" variant="ghost" aria-label={`删除 ${provider.id}`} onClick={onDelete}>
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  );
}
