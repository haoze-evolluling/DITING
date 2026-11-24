import { useState } from "react";
import { Route } from "lucide-react";

import { api, describeError } from "../../../lib/api";
import type { DiagnosticTraceResult } from "../../../lib/types";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import { Input } from "../../ui/input";
import { LoadingState } from "../../ui/loading";
import { Select } from "../../ui/select";
import { EmptyHint, ResultError, StatusLine, formatMs } from "./shared";

const HOP_OPTIONS = [
  { value: "16", label: "16 跳" },
  { value: "30", label: "30 跳" },
  { value: "64", label: "64 跳" },
];

export function TracePanel() {
  const [target, setTarget] = useState("");
  const [maxHops, setMaxHops] = useState("30");
  const [result, setResult] = useState<DiagnosticTraceResult | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function run() {
    const value = target.trim();
    if (!value) {
      setError("请输入路由追踪目标");
      return;
    }
    setLoading(true);
    setError("");
    try {
      setResult(await api.diagnoseTrace(value, Number(maxHops)));
    } catch (cause) {
      setResult(null);
      setError(describeError(cause));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <form
        className="flex flex-col gap-2 sm:flex-row"
        onSubmit={(event) => {
          event.preventDefault();
          void run();
        }}
      >
        <Input
          value={target}
          onChange={(event) => setTarget(event.target.value)}
          placeholder="域名或 IP，例如 one.one.one.one"
          aria-label="路由追踪目标"
          className="flex-1"
        />
        <Select
          value={maxHops}
          onValueChange={setMaxHops}
          options={HOP_OPTIONS}
          ariaLabel="最大跳数"
          className="sm:w-[100px]"
        />
        <Button type="submit" variant="primary" loading={loading}>
          <Route className="h-3.5 w-3.5" />
          开始追踪
        </Button>
      </form>

      {error ? <ResultError message={error} /> : null}

      {loading ? (
        <LoadingState label="正在逐跳追踪路由，最多需要几十秒…" className="min-h-[180px]" />
      ) : result ? (
        <div className="space-y-3">
          <StatusLine
            ok={result.reached}
            title={
              <span className="mono">
                {result.target} → {result.resolvedAddress}
              </span>
            }
            detail={
              result.reached
                ? `经过 ${result.hops.length} 跳到达目标。`
                : result.message || `经 ${result.hops.length} 跳仍未到达目标。`
            }
          />

          {result.hops.length > 0 ? (
            <div className="overflow-hidden rounded-xl border border-border">
              <div className="grid grid-cols-[64px_1fr_96px_1fr] gap-3 bg-surface-2 px-3 py-1.5 text-[10.5px] text-text-3">
                <span>跳数</span>
                <span>地址</span>
                <span>延迟</span>
                <span>状态</span>
              </div>
              {result.hops.map((hop) => (
                <div
                  key={hop.hop}
                  className="grid grid-cols-[64px_1fr_96px_1fr] items-center gap-3 border-t border-border/70 px-3 py-2 text-[11.5px]"
                >
                  <span className="num text-text-3">{hop.hop}</span>
                  <span className="mono truncate text-text">{hop.address ?? "*"}</span>
                  <span className="num text-text-2">{formatMs(hop.elapsedMs)}</span>
                  <span>
                    {hop.timeout ? (
                      <Badge tone="warn">无响应</Badge>
                    ) : hop.address ? (
                      <Badge tone="neutral">已应答</Badge>
                    ) : (
                      <Badge tone="warn">部分超时</Badge>
                    )}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <EmptyHint>没有解析到任何路由节点，请确认系统已安装 traceroute / tracert。</EmptyHint>
          )}
        </div>
      ) : !error ? (
        <EmptyHint>逐跳探测到目标的路由，用于定位链路中断或异常绕行。</EmptyHint>
      ) : null}
    </div>
  );
}
