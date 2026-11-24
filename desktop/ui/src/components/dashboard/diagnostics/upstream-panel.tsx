import { useState } from "react";
import { Gauge } from "lucide-react";

import { api, describeError } from "../../../lib/api";
import type { DiagnosticUpstreamResult } from "../../../lib/types";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import { Input } from "../../ui/input";
import { LoadingState } from "../../ui/loading";
import { Select } from "../../ui/select";
import { EmptyHint, ResultError, formatMs } from "./shared";

const ATTEMPT_OPTIONS = [
  { value: "1", label: "1 次" },
  { value: "3", label: "3 次" },
  { value: "5", label: "5 次" },
];

export function UpstreamPanel() {
  const [domain, setDomain] = useState("");
  const [attempts, setAttempts] = useState("3");
  const [results, setResults] = useState<DiagnosticUpstreamResult[] | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function run() {
    setLoading(true);
    setError("");
    try {
      setResults(await api.diagnoseUpstreams(domain.trim(), Number(attempts)));
    } catch (cause) {
      setResults(null);
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
          value={domain}
          onChange={(event) => setDomain(event.target.value)}
          placeholder="测试域名，留空使用 dns.alidns.com"
          aria-label="测试域名"
          className="flex-1"
        />
        <Select
          value={attempts}
          onValueChange={setAttempts}
          options={ATTEMPT_OPTIONS}
          ariaLabel="测试次数"
          className="sm:w-[100px]"
        />
        <Button type="submit" variant="primary" loading={loading}>
          <Gauge className="h-3.5 w-3.5" />
          测试上游
        </Button>
      </form>

      {error ? <ResultError message={error} /> : null}

      {loading ? (
        <LoadingState label="正在依次测试上游延迟…" className="min-h-[180px]" />
      ) : results ? (
        results.length > 0 ? (
          <div className="overflow-hidden rounded-xl border border-border">
            <div className="grid grid-cols-[1.4fr_90px_96px_1fr] gap-3 bg-surface-2 px-3 py-1.5 text-[10.5px] text-text-3">
              <span>上游</span>
              <span>协议</span>
              <span>平均延迟</span>
              <span>结果</span>
            </div>
            {results.map((result) => (
              <div
                key={result.id}
                className="grid grid-cols-[1.4fr_90px_96px_1fr] items-center gap-3 border-t border-border/70 px-3 py-2.5"
              >
                <div className="min-w-0">
                  <div className="truncate text-[12px] text-text">{result.id}</div>
                  <div className="mono truncate text-[10.5px] text-text-3">
                    {result.url || result.server}
                  </div>
                </div>
                <Badge tone="neutral">{result.protocol}</Badge>
                <span className="num text-[12px] text-text">
                  {result.success ? formatMs(result.latencyMs) : "—"}
                </span>
                <div className="min-w-0">
                  <Badge tone={result.success ? "good" : "danger"} dot>
                    {result.success
                      ? `${result.successCount}/${result.attempts} 成功`
                      : "不可用"}
                  </Badge>
                  {result.message ? (
                    <div className="mt-1 truncate text-[10.5px] text-text-3" title={result.message}>
                      {result.message}
                    </div>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <EmptyHint>尚未配置上游 DNS 服务器，请先到「上游解析」添加。</EmptyHint>
        )
      ) : !error ? (
        <EmptyHint>对配置中的每个上游重复查询同一域名，比较平均响应延迟。</EmptyHint>
      ) : null}
    </div>
  );
}
