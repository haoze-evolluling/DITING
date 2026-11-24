import { useState } from "react";
import { Search } from "lucide-react";

import { api, describeError } from "../../../lib/api";
import type { DiagnosticQueryResult } from "../../../lib/types";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import { Input } from "../../ui/input";
import { Select } from "../../ui/select";
import {
  EmptyHint,
  ResultError,
  ResultNotice,
  ResultTable,
  StatusLine,
  formatMs,
} from "./shared";

const QTYPE_OPTIONS = [
  { value: "A", label: "A" },
  { value: "AAAA", label: "AAAA" },
  { value: "CNAME", label: "CNAME" },
  { value: "TXT", label: "TXT" },
  { value: "MX", label: "MX" },
  { value: "NS", label: "NS" },
  { value: "PTR", label: "PTR" },
  { value: "SRV", label: "SRV" },
  { value: "HTTPS", label: "HTTPS" },
];

export function QueryPanel() {
  const [domain, setDomain] = useState("");
  const [qtype, setQtype] = useState("A");
  const [result, setResult] = useState<DiagnosticQueryResult | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function run() {
    const target = domain.trim();
    if (!target) {
      setError("请输入要查询的域名");
      return;
    }
    setLoading(true);
    setError("");
    try {
      setResult(await api.diagnoseQuery(target, qtype));
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
          value={domain}
          onChange={(event) => setDomain(event.target.value)}
          placeholder="例如 example.com"
          aria-label="查询域名"
          className="flex-1"
        />
        <Select
          value={qtype}
          onValueChange={setQtype}
          options={QTYPE_OPTIONS}
          ariaLabel="查询类型"
          className="sm:w-[112px]"
        />
        <Button type="submit" variant="primary" loading={loading}>
          <Search className="h-3.5 w-3.5" />
          查询
        </Button>
      </form>

      {error ? <ResultError message={error} /> : null}

      {result ? (
        <div className="space-y-3">
          <StatusLine
            ok={result.success}
            title={
              <span className="flex flex-wrap items-center gap-2">
                <span className="mono">{result.domain}</span>
                <Badge tone="neutral">{result.qtype}</Badge>
                <Badge tone={result.success ? "good" : "warn"}>{result.rcodeName}</Badge>
              </span>
            }
            detail={`耗时 ${formatMs(result.elapsedMs)} · ${
              result.source === "local"
                ? "本机 DNS（经规则与缓存）"
                : result.source === "upstream"
                  ? "直连上游（未经过本机监听）"
                  : result.source
            }`}
          />

          {result.message ? <ResultNotice tone="warn">{result.message}</ResultNotice> : null}

          {result.answers.length > 0 ? (
            <ResultTable columns={["记录", "类型", "TTL", "值"]}>
              {result.answers.map((answer, index) => (
                <div
                  key={`${answer.name}-${answer.recordType}-${index}`}
                  className="grid items-center gap-3 border-t border-border/70 px-3 py-2 text-[11.5px]"
                  style={{ gridTemplateColumns: "1.2fr 70px 60px 1.6fr" }}
                >
                  <span className="mono truncate text-text-2">{answer.name}</span>
                  <span className="text-text-3">{answer.recordType}</span>
                  <span className="num text-text-3">{answer.ttl}s</span>
                  <span className="mono break-all text-text">{answer.value}</span>
                </div>
              ))}
            </ResultTable>
          ) : (
            <EmptyHint>
              {result.success
                ? `查询成功，但没有返回 ${result.qtype} 记录。`
                : "没有可展示的应答记录。"}
            </EmptyHint>
          )}
        </div>
      ) : !error ? (
        <EmptyHint>
          输入域名后开始查询。DNS 运行时经过本机规则与缓存，未运行时直连上游。
        </EmptyHint>
      ) : null}
    </div>
  );
}
