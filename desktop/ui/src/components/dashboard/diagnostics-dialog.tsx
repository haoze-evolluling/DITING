import { useState } from "react";
import { Activity, Gauge, Route, Search, Send } from "lucide-react";

import type { StatusResponse } from "../../lib/types";
import { Button } from "../ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogHeader,
} from "../ui/dialog";
import { Segmented } from "../ui/segmented";
import { PingPanel } from "./diagnostics/ping-panel";
import { PortPanel } from "./diagnostics/port-panel";
import { QueryPanel } from "./diagnostics/query-panel";
import { TracePanel } from "./diagnostics/trace-panel";
import { UpstreamPanel } from "./diagnostics/upstream-panel";

type DiagnosticsTab = "port" | "query" | "upstreams" | "ping" | "trace";

const TABS = [
  { value: "port" as const, label: "端口", icon: Activity },
  { value: "query" as const, label: "DNS 查询", icon: Search },
  { value: "upstreams" as const, label: "上游延迟", icon: Gauge },
  { value: "ping" as const, label: "Ping", icon: Send },
  { value: "trace" as const, label: "路由追踪", icon: Route },
];

export function DiagnosticsDialog({
  open,
  onOpenChange,
  status,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  status?: StatusResponse;
}) {
  const [tab, setTab] = useState<DiagnosticsTab>("port");

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(760px,calc(100vw-40px))]">
        <DialogHeader
          title="网络诊断"
          description="检查端口占用，并测试 DNS 查询、上游延迟、Ping 与路由追踪。"
        />
        <DialogBody className="space-y-4">
          <Segmented value={tab} options={TABS} onChange={setTab} className="flex-wrap" />
          {tab === "port" ? <PortPanel open={open} status={status} /> : null}
          {tab === "query" ? <QueryPanel /> : null}
          {tab === "upstreams" ? <UpstreamPanel /> : null}
          {tab === "ping" ? <PingPanel /> : null}
          {tab === "trace" ? <TracePanel /> : null}
        </DialogBody>
        <DialogFooter>
          <Button size="sm" variant="primary" onClick={() => onOpenChange(false)}>
            完成
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
