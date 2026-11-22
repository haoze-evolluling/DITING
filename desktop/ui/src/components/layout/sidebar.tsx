import { NavLink } from "react-router-dom";
import { Gauge, ScrollText, Settings2 } from "lucide-react";

import { useStatus } from "../../hooks/use-api";
import { cn } from "../../lib/cn";
import { resolverModeLabel } from "../../lib/labels";
import { useLiveStore } from "../../stores/live";

const primaryNav = [
  { to: "/", label: "概览", icon: Gauge, end: true },
  { to: "/logs", label: "查询日志", icon: ScrollText, end: false },
];

const secondaryNav = [{ to: "/settings", label: "设置", icon: Settings2, end: false }];

function NavItem({
  to,
  label,
  icon: Icon,
  end,
}: {
  to: string;
  label: string;
  icon: typeof Gauge;
  end: boolean;
}) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        cn(
          "relative flex items-center gap-2.5 rounded-lg px-3 py-2 text-[13px] transition-colors",
          isActive
            ? "bg-accent-soft font-medium text-accent"
            : "text-text-2 hover:bg-surface-2 hover:text-text",
        )
      }
    >
      {({ isActive }) => (
        <>
          {isActive ? (
            <span className="absolute left-0 top-1/2 h-4 w-0.5 -translate-y-1/2 rounded-full bg-accent" />
          ) : null}
          <Icon className="h-4 w-4 shrink-0" />
          <span>{label}</span>
        </>
      )}
    </NavLink>
  );
}

export function Sidebar() {
  const status = useStatus();
  const connected = useLiveStore((state) => state.connected);
  const metrics = useLiveStore((state) => state.metrics);
  const dns = status.data?.dns;
  const running = dns?.running ?? false;
  const qps = metrics?.qps ?? status.data?.metrics.qps ?? 0;

  return (
    <aside className="hidden h-full w-[232px] shrink-0 flex-col border-r border-border bg-surface md:flex">
      <div className="flex items-center gap-2.5 px-5 pb-4 pt-5">
        <img
          src="/icon.webp"
          alt="谛听图标"
          className="h-9 w-9 rounded-xl object-cover shadow-sm ring-1 ring-border"
        />
        <div className="min-w-0">
          <div className="text-[15px] font-semibold tracking-[-0.02em] text-text">谛听</div>
          <div className="text-[9.5px] font-medium tracking-[0.22em] text-text-3">DITING DNS</div>
        </div>
      </div>

      <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-2">
        <div>
          <p className="px-3 pb-1.5 text-[10.5px] font-medium text-text-3">运行</p>
          <div className="space-y-0.5">
            {primaryNav.map((item) => (
              <NavItem key={item.to} {...item} />
            ))}
          </div>
        </div>
        <div>
          <p className="px-3 pb-1.5 text-[10.5px] font-medium text-text-3">管理</p>
          <div className="space-y-0.5">
            {secondaryNav.map((item) => (
              <NavItem key={item.to} {...item} />
            ))}
          </div>
        </div>
      </nav>

      <div className="px-3 pb-3">
        <div className="rounded-xl border border-border bg-surface-2 px-3 py-2.5">
          <div className="flex items-center justify-between text-[11.5px]">
            <span className="flex items-center gap-1.5 text-text-2">
              <span
                className={cn(
                  "h-1.5 w-1.5 rounded-full",
                  connected ? "bg-good" : "bg-warn",
                )}
              />
              {connected ? "实时连接" : "正在重连"}
            </span>
            <span className="text-[10px] tracking-[0.12em] text-text-3">WS</span>
          </div>
          <div className="mt-1.5 flex items-center justify-between text-[11px] text-text-3">
            <span>{running ? "DNS 运行中" : "DNS 已停止"}</span>
            <span className="num">{qps.toFixed(1)} QPS</span>
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between border-t border-border px-5 py-3 text-[10.5px] text-text-3">
        <span className="num">v{status.data?.version ?? __APP_VERSION__}</span>
        <span>{resolverModeLabel(dns?.mode)}</span>
      </div>
    </aside>
  );
}
