import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Code2, Save, SearchCheck } from "lucide-react";
import { toast } from "sonner";

import { useCustomRules } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { qtypeOptions } from "../../lib/labels";
import { joinLines, parseLines } from "../../lib/strings";
import type { CheckHostResult } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { LoadingState } from "../ui/loading";
import { Textarea } from "../ui/field";

export function CustomRulesCard() {
  const rules = useCustomRules();
  const queryClient = useQueryClient();
  const [text, setText] = useState("");
  const [domain, setDomain] = useState("");
  const [qtype, setQtype] = useState("A");
  const [checked, setChecked] = useState<CheckHostResult | null>(null);
  const [checkError, setCheckError] = useState<string | null>(null);

  useEffect(() => {
    if (rules.data) setText(joinLines(rules.data.rules));
  }, [rules.data]);

  const dirty = useMemo(
    () => rules.data !== undefined && text !== joinLines(rules.data.rules),
    [rules.data, text],
  );

  const save = useMutation({
    mutationFn: (lines: string[]) => api.saveCustomRules(lines),
    onSuccess: () => {
      toast.success("自定义规则已保存并生效");
      void queryClient.invalidateQueries({ queryKey: ["filter-rules"] });
      void queryClient.invalidateQueries({ queryKey: ["filter-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const check = useMutation({
    mutationFn: () => api.checkDomain(domain.trim(), qtype),
    onSuccess: (result) => {
      setChecked(result);
      setCheckError(null);
    },
    onError: (error) => {
      setChecked(null);
      setCheckError(describeError(error));
    },
  });

  const lineCount = parseLines(text).length;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="自定义规则"
        description="每行一条，语法与订阅源一致；在本地规则之后参与匹配。"
        actions={<Code2 className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col gap-3 pt-2">
        {rules.isLoading ? (
          <LoadingState label="正在加载自定义规则…" className="min-h-[180px]" />
        ) : (
          <Textarea
            className="min-h-[180px] font-mono text-[11.5px] leading-5"
            value={text}
            spellCheck={false}
            placeholder={"||ads.example.com^\n@@||good.example.com^\n0.0.0.0 tracker.example.com"}
            onChange={(event) => setText(event.target.value)}
          />
        )}

        <div className="rounded-xl border border-border bg-surface-2 px-3.5 py-3">
          <div className="flex items-center gap-1.5 text-[11.5px] text-text-2">
            <SearchCheck className="h-3.5 w-3.5 text-text-3" />
            规则检测
          </div>
          <div className="mt-2 flex flex-col gap-2 sm:flex-row">
            <Input
              value={domain}
              placeholder="输入域名，例如 example.com"
              className="mono sm:flex-1"
              onChange={(event) => setDomain(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter" && domain.trim()) check.mutate();
              }}
            />
            <Select
              className="shrink-0 sm:w-[130px]"
              value={qtype}
              options={qtypeOptions.filter((option) => option.value !== "all")}
              onValueChange={setQtype}
              ariaLabel="查询类型"
            />
            <Button
              className="shrink-0"
              variant="secondary"
              loading={check.isPending}
              disabled={!domain.trim()}
              onClick={() => check.mutate()}
            >
              检测
            </Button>
          </div>
          {checkError ? (
            <p className="mt-2 text-[11px] text-danger">{checkError}</p>
          ) : checked ? (
            <div className="mt-2 rounded-lg border border-border bg-surface px-3 py-2 text-[11px] leading-5">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={checked.blocked ? "danger" : "good"} dot>
                  {checked.blocked ? "将被拦截" : "放行"}
                </Badge>
                {checked.action ? <span className="text-text-3">动作 {checked.action}</span> : null}
                {checked.listName ? (
                  <span className="text-text-3">来源 {checked.listName}</span>
                ) : null}
              </div>
              {checked.matchedRule ? (
                <div className="mono mt-1 break-all text-text-2">{checked.matchedRule}</div>
              ) : null}
              {checked.reason ? <div className="mt-0.5 text-text-3">{checked.reason}</div> : null}
              {checked.rewritten?.summary?.length ? (
                <div className="mt-1 text-violet">{checked.rewritten.summary.join(" · ")}</div>
              ) : null}
            </div>
          ) : null}
        </div>
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {lineCount} 条规则{dirty ? " · 有未保存修改" : ""}
        </span>
        <Button
          size="sm"
          variant="primary"
          disabled={!dirty}
          loading={save.isPending}
          onClick={() => save.mutate(parseLines(text))}
        >
          <Save className="h-3.5 w-3.5" />
          保存规则
        </Button>
      </CardFooter>
    </Card>
  );
}
