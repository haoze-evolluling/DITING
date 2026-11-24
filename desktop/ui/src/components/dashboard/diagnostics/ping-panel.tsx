import { useState } from "react";
import { Send } from "lucide-react";

import { api, describeError } from "../../../lib/api";
import type { DiagnosticPingResult } from "../../../lib/types";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import { Input } from "../../ui/input";
import { LoadingState } from "../../ui/loading";
import { Select } from "../../ui/select";
import { EmptyHint, ResultError, StatusLine, formatMs } from "./shared";

const COUNT_OPTIONS = [
  { value: "1", label: "1 次" },
  { value: "4", label: "4 次" },
  { value: "8", label: "8 次" },
];

const TIMEOUT_OPTIONS = [
  { value: "1", label: "1 秒" },
  { value: "3", label: "3 秒" },
  { value: "5", label: "5 秒" },
];

export function PingPanel() {
  const [target, setTarget] = useState("");
  const [count, setCount] = useState("4");
  const [timeoutSeconds, setTimeoutSeconds] = useState("3");
  const [result, setResult] = useState<DiagnosticPingResult | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function run() {
    const value = target.trim();
    if (!value) {
      setError("请输入 Ping 目标");
      return;
    }
    setLoading(true);
    setError("");
    try {
      setResult(await api.diagnosePing(value, Number(count), Number(timeoutSeconds)));
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
          placeholder="域名或 IP，例如 1.1.1.1"
          aria-label="Ping 目标"
          className="flex-1"
        />
        <Select
          value={count}
          onValueChange={setCount}
          options={COUNT_OPTIONS}
          ariaLabel="Ping 次数"
          className="sm:w-[90px]"
        />
        <Select
          value={timeoutSeconds}
          onValueChange={setTimeoutSeconds}
          options={TIMEOUT_OPTIONS}
          ariaLabel="单次超时"
          className="sm:w-[92px]"
        />
        <Button type="submit" variant="primary" loading={loading}>
          <Send className="h-3.5 w-3.5" />
          开始 Ping
        </Button>
      </form>

      {error ? <ResultError message={error} /> : null}

      {loading ? (
        <LoadingState label="正在发送 ICMP 探测…" className="min-h-[180px]" />
      ) : result ? (
        <div className="space-y-3">
          <StatusLine
            ok={result.success}
            title={
              <span className="mono">
                {result.target} → {result.resolvedAddress}
              </span>
            }
            detail={`${result.addressFamily} · 接收 ${result.received}/${result.transmitted} · 丢包 ${result.lossPercent.toFixed(
              result.lossPercent % 1 === 0 ? 0 : 1,
            )}%`}
          />

          {result.message ? (
            <div className="rounded-xl border border-warn/25 bg-warn-soft px-3.5 py-2.5 text-[11.5px] leading-5 text-warn">
              {result.message}
            </div>
          ) : null}

          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[
              { label: "最小延迟", value: formatMs(result.minMs) },
              { label: "平均延迟", value: formatMs(result.avgMs) },
              { label: "最大延迟", value: formatMs(result.maxMs) },
              { label: "抖动", value: formatMs(result.jitterMs) },
            ].map((item) => (
              <div
                key={item.label}
                className="rounded-xl border border-border bg-surface-2 px-3 py-2"
              >
                <div className="text-[10.5px] text-text-3">{item.label}</div>
                <div className="num mt-0.5 text-[14px] font-medium text-text">{item.value}</div>
              </div>
            ))}
          </div>

          <div className="overflow-hidden rounded-xl border border-border">
            <div className="grid grid-cols-[64px_1fr_80px_1fr] gap-3 bg-surface-2 px-3 py-1.5 text-[10.5px] text-text-3">
              <span>序号</span>
              <span>延迟</span>
              <span>TTL</span>
              <span>状态</span>
            </div>
            {result.replies.map((reply) => (
              <div
                key={reply.sequence}
                className="grid grid-cols-[64px_1fr_80px_1fr] items-center gap-3 border-t border-border/70 px-3 py-2 text-[11.5px]"
              >
                <span className="num text-text-3">#{reply.sequence}</span>
                <span className="num text-text">{formatMs(reply.elapsedMs)}</span>
                <span className="num text-text-2">{reply.ttl ?? "—"}</span>
                <span>
                  {reply.timeout ? (
                    <Badge tone="warn">超时</Badge>
                  ) : (
                    <Badge tone="good">已响应</Badge>
                  )}
                </span>
              </div>
            ))}
          </div>
        </div>
      ) : !error ? (
        <EmptyHint>向目标发送 ICMP 回显请求，检查连通性、丢包与延迟抖动。</EmptyHint>
      ) : null}
    </div>
  );
}
