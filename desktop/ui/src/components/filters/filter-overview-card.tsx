import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { PauseCircle, PlayCircle, ShieldBan } from "lucide-react";
import { toast } from "sonner";

import { useFilterConfig, useFilterPause, useStatus } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber, formatPercent } from "../../lib/format";
import { SwitchRowsSkeleton } from "../skeletons/parts";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { Select } from "../ui/select";
import { Skeleton } from "../ui/skeleton";
import { SwitchRow } from "../ui/switch-row";

const durationOptions = [
  { value: "300", label: "5 分钟" },
  { value: "1800", label: "30 分钟" },
  { value: "3600", label: "1 小时" },
  { value: "21600", label: "6 小时" },
  { value: "86400", label: "24 小时" },
];

function remainingLabel(seconds: number): string {
  if (seconds <= 0) return "即将恢复";
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours} 小时 ${minutes} 分`;
  return `${Math.max(minutes, 1)} 分钟`;
}

export function FilterOverviewCard() {
  const status = useStatus();
  const config = useFilterConfig();
  const pause = useFilterPause();
  const queryClient = useQueryClient();
  const [duration, setDuration] = useState("3600");

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["status"] });
    void queryClient.invalidateQueries({ queryKey: ["filter-config"] });
    void queryClient.invalidateQueries({ queryKey: ["filter-pause"] });
  };

  const toggle = useMutation({
    mutationFn: (enabled: boolean) => api.updateFilterConfig({ enabled }),
    onSuccess: (_, enabled) => {
      toast.success(enabled ? "拦截已启用" : "拦截已停用");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const setPause = useMutation({
    mutationFn: (input: { paused: boolean; duration: number }) =>
      api.setFilterPause(input.paused, input.duration),
    onSuccess: (_, input) => {
      toast.success(input.paused ? "拦截已暂停" : "拦截已恢复");
      invalidate();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const stats = status.data?.filter;
  const paused = pause.data?.paused ?? false;
  const enabled = config.data?.enabled ?? true;

  return (
    <Card>
      <CardHeader
        title="拦截状态"
        description="规则匹配、订阅索引与临时暂停。"
        actions={<ShieldBan className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="pt-1">
        {status.isLoading || config.isLoading ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={1} />
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {Array.from({ length: 4 }).map((_, index) => (
                <Skeleton key={index} className="h-[62px] w-full rounded-xl" />
              ))}
            </div>
            <Skeleton className="h-[68px] w-full rounded-xl" />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用拦截"
              description={enabled ? "规则与订阅正在参与解析" : "所有域名将直接放行"}
              checked={enabled}
              onCheckedChange={(value) => toggle.mutate(value)}
              disabled={toggle.isPending}
            />

            <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
              {[
                { label: "规则总数", value: formatNumber(stats?.totalRules) },
                { label: "活跃订阅", value: formatNumber(stats?.activeLists) },
                { label: "拦截请求", value: formatNumber(stats?.blockedQueries) },
                { label: "拦截率", value: formatPercent(stats?.blockRate) },
              ].map((item) => (
                <div
                  key={item.label}
                  className="rounded-xl border border-border bg-surface-2 px-3 py-2.5"
                >
                  <div className="num text-[17px] font-semibold leading-6 text-text">
                    {item.value}
                  </div>
                  <div className="mt-0.5 text-[10.5px] text-text-3">{item.label}</div>
                </div>
              ))}
            </div>

            <div className="mt-3 rounded-xl border border-border bg-surface-2 px-3.5 py-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2 text-[12px] text-text">
                    临时暂停
                    {paused ? (
                      <Badge tone="warn" dot>
                        已暂停
                      </Badge>
                    ) : null}
                    {stats?.scheduleActive ? <Badge tone="accent">时间计划生效中</Badge> : null}
                  </div>
                  <div className="mt-0.5 text-[10.5px] text-text-3">
                    {paused
                      ? `剩余 ${remainingLabel(pause.data?.remainingSeconds ?? 0)}，到点自动恢复`
                      : "暂停期间所有域名直接放行，适合临时排障"}
                  </div>
                </div>
                {paused ? (
                  <Button
                    size="sm"
                    variant="secondary"
                    loading={setPause.isPending}
                    onClick={() => setPause.mutate({ paused: false, duration: 0 })}
                  >
                    <PlayCircle className="h-3.5 w-3.5" />
                    立即恢复
                  </Button>
                ) : (
                  <div className="flex items-center gap-2">
                    <Select
                      className="h-8 w-[118px] shrink-0"
                      value={duration}
                      options={durationOptions}
                      onValueChange={setDuration}
                      ariaLabel="暂停时长"
                    />
                    <Button
                      size="sm"
                      variant="secondary"
                      className="shrink-0"
                      loading={setPause.isPending}
                      onClick={() => setPause.mutate({ paused: true, duration: Number(duration) })}
                    >
                      <PauseCircle className="h-3.5 w-3.5" />
                      暂停
                    </Button>
                  </div>
                )}
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
