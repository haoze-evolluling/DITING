import type { FormEvent } from "react";
import { Search, Trash2, Users } from "lucide-react";

import { qtypeOptions, statusOptions } from "../../lib/labels";
import { Button } from "../ui/button";
import { Card } from "../ui/card";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { Switch } from "../ui/switch";

export interface LogFilters {
  domain: string;
  client: string;
  status: string;
  qtype: string;
}

export function LogToolbar({
  filters,
  onChange,
  live,
  onLiveChange,
  onSubmit,
  onReset,
  onClear,
  clearing,
}: {
  filters: LogFilters;
  onChange: (patch: Partial<LogFilters>) => void;
  live: boolean;
  onLiveChange: (live: boolean) => void;
  onSubmit: () => void;
  onReset: () => void;
  onClear: () => void;
  clearing: boolean;
}) {
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSubmit();
  };

  return (
    <Card>
      <form onSubmit={submit}>
        <div className="flex flex-wrap items-center gap-2 px-3.5 pt-3">
          <Input
            value={filters.domain}
            onChange={(event) => onChange({ domain: event.target.value })}
            leading={<Search className="h-3.5 w-3.5" />}
            placeholder="搜索域名"
            className="min-w-[170px] flex-1"
            aria-label="搜索域名"
          />
          <Input
            value={filters.client}
            onChange={(event) => onChange({ client: event.target.value })}
            leading={<Users className="h-3.5 w-3.5" />}
            placeholder="客户端 IP 或名称"
            className="min-w-[160px] flex-1"
            aria-label="搜索客户端"
          />
          <Select
            value={filters.status || "all"}
            onValueChange={(value) => onChange({ status: value === "all" ? "" : value })}
            options={statusOptions}
            className="w-[136px] shrink-0"
            ariaLabel="筛选状态"
          />
          <Select
            value={filters.qtype || "all"}
            onValueChange={(value) => onChange({ qtype: value === "all" ? "" : value })}
            options={qtypeOptions}
            className="w-[118px] shrink-0"
            ariaLabel="筛选记录类型"
          />
          <Button type="submit" size="sm" variant="primary" className="shrink-0">
            查询
          </Button>
          <Button type="button" size="sm" variant="ghost" className="shrink-0" onClick={onReset}>
            重置
          </Button>
        </div>

        <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 border-t border-border/70 px-3.5 py-2">
          <span className="text-[10.5px] text-text-3">
            {live
              ? "实时模式仅显示本次会话收到的请求，最多保留 400 条。"
              : "历史模式检索内存与 SQLite 数据库中的查询日志。"}
          </span>
          <div className="flex items-center gap-2">
            <label className="flex cursor-pointer items-center gap-2 text-[11.5px] text-text-2">
              <Switch checked={live} onCheckedChange={onLiveChange} label="切换实时查询流" />
              {live ? "实时" : "历史"}
            </label>
            <Button
              type="button"
              size="sm"
              variant="dangerSoft"
              onClick={onClear}
              loading={clearing}
            >
              <Trash2 className="h-3.5 w-3.5" />
              清空
            </Button>
          </div>
        </div>
      </form>
    </Card>
  );
}
