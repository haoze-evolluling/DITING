import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Blocks, Save } from "lucide-react";
import { toast } from "sonner";

import { useBlockedServices } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { formatNumber } from "../../lib/format";
import { cn } from "../../lib/cn";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Skeleton } from "../ui/skeleton";

function sameSet(a: Set<string>, b: Set<string>): boolean {
  if (a.size !== b.size) return false;
  for (const value of a) if (!b.has(value)) return false;
  return true;
}

export function BlockedServicesCard({ onSchedule }: { onSchedule?: () => void }) {
  const data = useBlockedServices();
  const queryClient = useQueryClient();
  const [ids, setIds] = useState<Set<string>>(new Set());
  const [groups, setGroups] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!data.data) return;
    setIds(new Set(data.data.blockedIds));
    setGroups(new Set(data.data.blockedGroups));
  }, [data.data]);

  const dirty = useMemo(() => {
    if (!data.data) return false;
    return (
      !sameSet(ids, new Set(data.data.blockedIds)) ||
      !sameSet(groups, new Set(data.data.blockedGroups))
    );
  }, [data.data, ids, groups]);

  const save = useMutation({
    mutationFn: () =>
      api.configureBlockedServices({ ids: [...ids], groups: [...groups] }),
    onSuccess: (result) => {
      toast.success(`已拦截 ${result.activeRules} 条内置服务规则`);
      void queryClient.invalidateQueries({ queryKey: ["blocked-services"] });
      void queryClient.invalidateQueries({ queryKey: ["filter-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const toggleGroup = (groupId: string, members: string[]) => {
    setGroups((current) => {
      const next = new Set(current);
      if (next.has(groupId)) next.delete(groupId);
      else next.add(groupId);
      return next;
    });
    setIds((current) => {
      const next = new Set(current);
      for (const id of members) next.delete(id);
      return next;
    });
  };

  const toggleService = (serviceId: string) => {
    setIds((current) => {
      const next = new Set(current);
      if (next.has(serviceId)) next.delete(serviceId);
      else next.add(serviceId);
      return next;
    });
  };

  const services = data.data?.services ?? [];
  const groupsInfo = data.data?.groups ?? [];

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="内置服务拦截"
        description="按应用或整组阻断内置域名，规则随服务端目录更新。"
        actions={
          <Badge tone={ids.size + groups.size > 0 ? "danger" : "neutral"}>
            {ids.size + groups.size > 0
              ? `${formatNumber(data.data?.activeRules)} 条生效`
              : "未拦截"}
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col gap-3 pt-2">
        {data.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : (
          groupsInfo.map((group) => {
            const members = services.filter((service) => service.group === group.id);
            const groupSelected = groups.has(group.id);
            return (
              <div key={group.id} className="rounded-xl border border-border bg-surface-2 p-3">
                <div className="flex items-center justify-between gap-2">
                  <button
                    type="button"
                    onClick={() => toggleGroup(group.id, members.map((service) => service.id))}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-[11.5px] font-medium transition-colors",
                      groupSelected
                        ? "bg-danger-soft text-danger"
                        : "text-text-2 hover:bg-surface-3",
                    )}
                  >
                    <Blocks className="h-3.5 w-3.5" />
                    {group.name}
                  </button>
                  <span className="text-[10.5px] text-text-3">{group.count} 项</span>
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {members.map((service) => {
                    const active = groupSelected || ids.has(service.id);
                    return (
                      <button
                        key={service.id}
                        type="button"
                        disabled={groupSelected}
                        title={
                          groupSelected
                            ? `已整组拦截「${group.name}」`
                            : `${service.name} · ${service.ruleCount} 条规则`
                        }
                        onClick={() => toggleService(service.id)}
                        className={cn(
                          "rounded-lg border px-2 py-1 text-[11px] transition-colors",
                          active
                            ? "border-danger/25 bg-danger-soft text-danger"
                            : "border-border bg-surface text-text-2 hover:bg-surface-3",
                          groupSelected && "cursor-not-allowed opacity-70",
                        )}
                      >
                        {service.name}
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })
        )}
        <p className="text-[10.5px] leading-4 text-text-3">
          整组拦截会覆盖组内单项；需要放行个别服务时请先取消整组。按周计划放行可在“时间计划”中配置。
        </p>
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {dirty ? "存在未保存修改" : "配置已同步"}
        </span>
        <div className="flex items-center gap-2">
          {onSchedule ? (
            <Button size="sm" variant="ghost" onClick={onSchedule}>
              时间计划
            </Button>
          ) : null}
          <Button
            size="sm"
            variant="primary"
            disabled={!dirty}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            <Save className="h-3.5 w-3.5" />
            保存
          </Button>
        </div>
      </CardFooter>
    </Card>
  );
}
