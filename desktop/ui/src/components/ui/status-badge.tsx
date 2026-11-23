import {
  CircleAlert,
  CircleCheck,
  History,
  ShieldBan,
  Zap,
  type LucideIcon,
} from "lucide-react";

import { Badge } from "./badge";

type QueryStatus = "allowed" | "blocked" | "cached" | "stale" | "error";

const meta: Record<
  QueryStatus,
  { label: string; tone: "good" | "danger" | "violet" | "warn" | "neutral"; icon: LucideIcon }
> = {
  allowed: { label: "允许", tone: "good", icon: CircleCheck },
  blocked: { label: "拦截", tone: "danger", icon: ShieldBan },
  cached: { label: "缓存", tone: "violet", icon: Zap },
  stale: { label: "过期缓存", tone: "warn", icon: History },
  error: { label: "失败", tone: "danger", icon: CircleAlert },
};

export function normalizeQueryStatus(status: string | undefined): QueryStatus {
  if (status === "blocked") return "blocked";
  if (status === "cached") return "cached";
  if (status === "stale") return "stale";
  if (status === "error") return "error";
  return "allowed";
}

export function StatusBadge({ status }: { status: string | undefined }) {
  const current = meta[normalizeQueryStatus(status)];
  const Icon = current.icon;
  return (
    <Badge tone={current.tone}>
      <Icon className="h-3 w-3" />
      {current.label}
    </Badge>
  );
}
