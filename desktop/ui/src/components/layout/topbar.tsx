import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import {
  Check,
  Gauge,
  Globe2,
  LockKeyhole,
  LogOut,
  Monitor,
  Moon,
  Network,
  ScrollText,
  Settings2,
  ShieldBan,
  Sparkles,
  Sun,
  UserRound,
} from "lucide-react";
import { NavLink } from "react-router-dom";

import { useStatus } from "../../hooks/use-api";
import { useLogout } from "../../hooks/use-logout";
import { MOTION_LEVEL_OPTIONS, useMotion } from "../../hooks/use-motion";
import { cn } from "../../lib/cn";
import { prefetchRoute } from "../../lib/route-prefetch";
import { useAuthStore } from "../../stores/auth";
import { useLiveStore } from "../../stores/live";
import { useUIStore, type ThemeMode } from "../../stores/ui";

const themeOptions: { value: ThemeMode; label: string; icon: typeof Sun }[] = [
  { value: "system", label: "跟随系统", icon: Monitor },
  { value: "light", label: "浅色", icon: Sun },
  { value: "dark", label: "深色", icon: Moon },
];

const menuClass =
  "motion-popover z-[70] min-w-[208px] rounded-xl border border-border bg-surface p-1 shadow-[var(--shadow-pop)]";
const itemClass =
  "flex cursor-pointer select-none items-center gap-2 rounded-lg px-2.5 py-1.5 text-[12.5px] text-text outline-none data-[highlighted]:bg-surface-3";

function MobileNav() {
  const items = [
    { to: "/", label: "概览", icon: Gauge, end: true },
    { to: "/logs", label: "日志", icon: ScrollText, end: false },
    { to: "/filter", label: "规则", icon: ShieldBan, end: false },
    { to: "/upstream", label: "上游", icon: Globe2, end: false },
    { to: "/lan", label: "局域网", icon: Network, end: false },
    { to: "/encrypted", label: "加密", icon: LockKeyhole, end: false },
    { to: "/settings", label: "设置", icon: Settings2, end: false },
  ];
  return (
    <nav className="flex max-w-[calc(100vw-150px)] items-center gap-0.5 overflow-x-auto md:hidden">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.end}
          onMouseEnter={() => prefetchRoute(item.to)}
          onFocus={() => prefetchRoute(item.to)}
          className={({ isActive }) =>
            cn(
              "flex h-8 w-8 items-center justify-center rounded-lg transition-colors",
              isActive ? "bg-accent-soft text-accent" : "text-text-3 hover:text-text",
            )
          }
          aria-label={item.label}
        >
          <item.icon className="h-4 w-4" />
        </NavLink>
      ))}
    </nav>
  );
}

export function Topbar() {
  const status = useStatus();
  const metrics = useLiveStore((state) => state.metrics);
  const connected = useLiveStore((state) => state.connected);
  const theme = useUIStore((state) => state.theme);
  const setTheme = useUIStore((state) => state.setTheme);
  const { effective: motion, isSystemDefault, setMotion } = useMotion();
  const username = useAuthStore((state) => state.username);
  const logout = useLogout();

  const running = status.data?.dns.running ?? false;
  const qps = metrics?.qps ?? status.data?.metrics.qps ?? 0;
  const ThemeIcon =
    themeOptions.find((option) => option.value === theme)?.icon ?? Monitor;

  return (
    <header className="motion-glass flex h-14 shrink-0 items-center justify-between gap-3 border-b border-border bg-[color-mix(in_oklab,var(--surface)_82%,transparent)] px-4 backdrop-blur-xl lg:px-6">
      <div className="flex items-center gap-2.5">
        <img src="/icon.webp" alt="" className="h-6 w-6 rounded-lg md:hidden" />
        <MobileNav />
        <div className="hidden items-center gap-3 md:flex">
          <span
            className={cn(
              "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-[3px] text-[11.5px] font-medium",
              running
                ? "border-good/25 bg-good-soft text-good"
                : "border-border bg-surface-2 text-text-3",
            )}
          >
            <span
              className={cn(
                "live-dot h-1.5 w-1.5 rounded-full",
                running ? "bg-good" : "bg-text-3",
              )}
            />
            {running ? "DNS 运行中" : "DNS 未启动"}
          </span>
          <span className="text-[11.5px] text-text-3">实时链路</span>
          <span
            className={cn(
              "h-1.5 w-1.5 rounded-full",
              connected ? "bg-good" : "bg-warn",
            )}
            title={connected ? "WebSocket 已连接" : "WebSocket 重连中"}
          />
          <span className="num text-[11.5px] text-text-3">{qps.toFixed(1)} QPS</span>
        </div>
      </div>

      <div className="flex items-center gap-1">
        <DropdownMenu.Root>
          <DropdownMenu.Trigger asChild>
            <button
              type="button"
              aria-label="外观与动画设置"
              className="motion-btn flex h-8 w-8 items-center justify-center rounded-lg text-text-2 hover:bg-surface-3 hover:text-text"
            >
              <ThemeIcon className="h-4 w-4" />
            </button>
          </DropdownMenu.Trigger>
          <DropdownMenu.Portal>
            <DropdownMenu.Content align="end" sideOffset={6} className={menuClass}>
              <DropdownMenu.Label className="px-2.5 py-1 text-[10.5px] text-text-3">
                外观主题
              </DropdownMenu.Label>
              {themeOptions.map((option) => (
                <DropdownMenu.Item
                  key={option.value}
                  onSelect={() => setTheme(option.value)}
                  className={itemClass}
                >
                  <option.icon className="h-3.5 w-3.5 text-text-3" />
                  <span className="flex-1">{option.label}</span>
                  {theme === option.value ? <Check className="h-3.5 w-3.5 text-accent" /> : null}
                </DropdownMenu.Item>
              ))}
              <DropdownMenu.Separator className="my-1 h-px bg-border" />
              <DropdownMenu.Label className="flex items-center justify-between px-2.5 py-1 text-[10.5px] text-text-3">
                <span className="inline-flex items-center gap-1.5">
                  <Sparkles className="h-3 w-3" />
                  动画效果
                </span>
                {isSystemDefault ? <span>默认</span> : null}
              </DropdownMenu.Label>
              {MOTION_LEVEL_OPTIONS.map((option) => (
                <DropdownMenu.Item
                  key={option.value}
                  onSelect={() => setMotion(option.value)}
                  className={itemClass}
                >
                  <span className="flex-1">{option.label}</span>
                  <span className="text-[10.5px] text-text-3">{option.performance}</span>
                  {motion === option.value ? (
                    <Check className="h-3.5 w-3.5 shrink-0 text-accent" />
                  ) : (
                    <span className="h-3.5 w-3.5 shrink-0" />
                  )}
                </DropdownMenu.Item>
              ))}
            </DropdownMenu.Content>
          </DropdownMenu.Portal>
        </DropdownMenu.Root>

        <span className="mx-1 h-5 w-px bg-border" />

        <DropdownMenu.Root>
          <DropdownMenu.Trigger asChild>
            <button
              type="button"
              className="motion-btn flex h-8 items-center gap-2 rounded-lg pl-1 pr-2 hover:bg-surface-3"
            >
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-accent-soft text-[11px] font-semibold text-accent">
                {(username ?? "A").slice(0, 1).toUpperCase()}
              </span>
              <span className="hidden text-[12.5px] text-text-2 sm:inline">
                {username ?? "admin"}
              </span>
            </button>
          </DropdownMenu.Trigger>
          <DropdownMenu.Portal>
            <DropdownMenu.Content align="end" sideOffset={6} className={menuClass}>
              <DropdownMenu.Label className="px-2.5 py-1.5">
                <div className="flex items-center gap-1.5 text-[12.5px] font-medium text-text">
                  <UserRound className="h-3.5 w-3.5 text-text-3" />
                  {username ?? "admin"}
                </div>
                <div className="mt-0.5 text-[11px] text-text-3">管理员账户</div>
              </DropdownMenu.Label>
              <DropdownMenu.Separator className="my-1 h-px bg-border" />
              <DropdownMenu.Item
                onSelect={() => void logout()}
                className={cn(itemClass, "text-danger data-[highlighted]:bg-danger-soft")}
              >
                <LogOut className="h-3.5 w-3.5" />
                退出登录
              </DropdownMenu.Item>
            </DropdownMenu.Content>
          </DropdownMenu.Portal>
        </DropdownMenu.Root>
      </div>
    </header>
  );
}
