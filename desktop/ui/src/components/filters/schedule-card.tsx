import { useEffect, useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CalendarClock, Pencil, Plus, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { useFilterSchedule } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import { cn } from "../../lib/cn";
import type { BlockingSchedule } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { FieldGridSkeleton, SwitchRowsSkeleton } from "../skeletons/parts";
import { Switch } from "../ui/switch";
import { SwitchRow } from "../ui/switch-row";

const weekdays = [
  { key: "mon", label: "一" },
  { key: "tue", label: "二" },
  { key: "wed", label: "三" },
  { key: "thu", label: "四" },
  { key: "fri", label: "五" },
  { key: "sat", label: "六" },
  { key: "sun", label: "日" },
];

function weekdayLabel(days: string[]): string {
  if (days.length === 0 || days.length === 7) return "每天";
  return weekdays
    .filter((day) => days.some((value) => value.toLowerCase().startsWith(day.key)))
    .map((day) => day.label)
    .join(" ");
}

const emptySchedule: BlockingSchedule = {
  id: "",
  name: "",
  enabled: true,
  weekdays: weekdays.map((day) => day.key),
  start: "08:00",
  end: "18:00",
};

function ScheduleDialog({
  open,
  onOpenChange,
  initial,
  onSubmit,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: BlockingSchedule | null;
  onSubmit: (schedule: BlockingSchedule) => void;
}) {
  const [draft, setDraft] = useState<BlockingSchedule>(emptySchedule);

  useEffect(() => {
    if (!open) return;
    setDraft(initial ? { ...initial } : { ...emptySchedule });
  }, [open, initial]);

  const toggleDay = (key: string) =>
    setDraft((current) => {
      const has = current.weekdays.includes(key);
      return {
        ...current,
        weekdays: has
          ? current.weekdays.filter((day) => day !== key)
          : [...current.weekdays, key],
      };
    });

  const valid = draft.name.trim().length > 0 && Boolean(draft.start) && Boolean(draft.end);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(520px,calc(100vw-40px))]">
        <DialogHeader
          title={initial ? "编辑时间计划" : "添加时间计划"}
          description="仅启用的计划会参与拦截判断；跨天时段自动衔接。"
        />
        <DialogBody className="space-y-3.5">
          <Field label="名称">
            <Input
              value={draft.name}
              placeholder="例如：工作时段"
              onChange={(event) => setDraft((c) => ({ ...c, name: event.target.value }))}
            />
          </Field>

          <div>
            <span className="text-[12px] text-text">生效星期</span>
            <div className="mt-1.5 flex flex-wrap gap-1.5">
              {weekdays.map((day) => {
                const active = draft.weekdays.includes(day.key);
                return (
                  <button
                    key={day.key}
                    type="button"
                    aria-pressed={active}
                    onClick={() => toggleDay(day.key)}
                    className={cn(
                      "h-8 w-9 rounded-lg border text-[12px] transition-colors",
                      active
                        ? "border-accent bg-accent-soft text-accent"
                        : "border-border bg-surface-2 text-text-3 hover:bg-surface-3",
                    )}
                  >
                    {day.label}
                  </button>
                );
              })}
            </div>
            <span className="mt-1 block text-[10.5px] text-text-3">不选择表示每天生效</span>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="开始时间">
              <Input
                type="time"
                value={draft.start}
                onChange={(event) => setDraft((c) => ({ ...c, start: event.target.value }))}
              />
            </Field>
            <Field label="结束时间">
              <Input
                type="time"
                value={draft.end}
                onChange={(event) => setDraft((c) => ({ ...c, end: event.target.value }))}
              />
            </Field>
          </div>

          <SwitchRow
            title="启用该计划"
            checked={draft.enabled}
            onCheckedChange={(enabled) => setDraft((c) => ({ ...c, enabled }))}
          />
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            取消
          </Button>
          <Button
            variant="primary"
            disabled={!valid}
            onClick={() => {
              onSubmit({ ...draft, name: draft.name.trim() });
              onOpenChange(false);
            }}
          >
            保存
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function ScheduleCard() {
  const schedule = useFilterSchedule();
  const queryClient = useQueryClient();
  const [enabled, setEnabled] = useState(false);
  const [schedules, setSchedules] = useState<BlockingSchedule[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<BlockingSchedule | null>(null);
  const scheduleKey = JSON.stringify(
    schedule.data ? { enabled: schedule.data.enabled, schedules: schedule.data.schedules } : null,
  );

  useEffect(() => {
    if (!schedule.data) return;
    setEnabled(schedule.data.enabled);
    setSchedules(schedule.data.schedules.map((item) => ({ ...item })));
    // 仅在服务端配置实际变化时重置草稿。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scheduleKey]);

  const dirty = useMemo(() => {
    if (!schedule.data) return false;
    return (
      enabled !== schedule.data.enabled ||
      JSON.stringify(schedules) !== JSON.stringify(schedule.data.schedules)
    );
  }, [schedule.data, enabled, schedules]);

  const save = useMutation({
    mutationFn: () => api.configureSchedule({ enabled, schedules }),
    onSuccess: () => {
      toast.success("时间计划已保存并生效");
      void queryClient.invalidateQueries({ queryKey: ["filter-schedule"] });
      void queryClient.invalidateQueries({ queryKey: ["filter-config"] });
      void queryClient.invalidateQueries({ queryKey: ["status"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const submit = (draft: BlockingSchedule) => {
    setSchedules((current) => {
      const index = current.findIndex((item) => item.id === editing?.id);
      if (index < 0) return [...current, draft];
      return current.map((item, position) => (position === index ? draft : item));
    });
    setEditing(null);
  };

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="时间计划"
        description="在指定时段内启用拦截，其余时间放行。"
        actions={
          <Button
            size="sm"
            variant="secondary"
            onClick={() => {
              setEditing(null);
              setDialogOpen(true);
            }}
          >
            <Plus className="h-3.5 w-3.5" />
            添加
          </Button>
        }
      />
      <CardContent className="flex flex-1 flex-col pt-1">
        {schedule.isLoading ? (
          <div className="space-y-3">
            <SwitchRowsSkeleton rows={1} />
            <FieldGridSkeleton fields={2} />
          </div>
        ) : (
          <>
            <SwitchRow
              title="启用时间计划"
              description="关闭后所有计划暂停，拦截恢复为全天候"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
            <div className="mt-2 space-y-2">
              {schedules.length === 0 ? (
                <div className="flex items-center gap-2 rounded-xl border border-dashed border-border bg-surface-2 px-3 py-4 text-[11.5px] text-text-3">
                  <CalendarClock className="h-4 w-4" />
                  还没有时间计划
                </div>
              ) : (
                schedules.map((item) => {
                  const active = schedule.data?.activeId === item.id;
                  return (
                    <div
                      key={item.id || item.name}
                      className="flex items-center gap-2.5 rounded-xl border border-border bg-surface-2 px-3 py-2.5"
                    >
                      <Switch
                        checked={item.enabled}
                        label={`启用 ${item.name}`}
                        onCheckedChange={(value) =>
                          setSchedules((current) =>
                            current.map((entry) =>
                              entry === item ? { ...entry, enabled: value } : entry,
                            ),
                          )
                        }
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="truncate text-[12px] text-text">{item.name}</span>
                          {active ? <Badge tone="accent">当前生效</Badge> : null}
                        </div>
                        <div className="mt-0.5 text-[10.5px] text-text-3">
                          {weekdayLabel(item.weekdays)} · {item.start} – {item.end}
                        </div>
                      </div>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={`编辑 ${item.name}`}
                        onClick={() => {
                          setEditing(item);
                          setDialogOpen(true);
                        }}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={`删除 ${item.name}`}
                        onClick={() =>
                          setSchedules((current) => current.filter((entry) => entry !== item))
                        }
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  );
                })
              )}
            </div>
          </>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {dirty ? "存在未保存修改" : "配置已同步"}
        </span>
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
      </CardFooter>

      <ScheduleDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        initial={editing}
        onSubmit={submit}
      />
    </Card>
  );
}
