export const resolverModeOptions = [
  { value: "single", label: "单一上游" },
  { value: "primary_backup", label: "主备切换" },
  { value: "parallel_race", label: "并发竞速" },
  { value: "smart_prediction", label: "智能选择" },
];

export function resolverModeLabel(mode: string | undefined): string {
  return resolverModeOptions.find((option) => option.value === mode)?.label ?? mode ?? "—";
}

export function protocolLabel(protocol: string | undefined): string {
  switch ((protocol ?? "").toUpperCase()) {
    case "DOH":
      return "DoH";
    case "DOT":
      return "DoT";
    case "PLAIN":
      return "UDP";
    default:
      return protocol || "—";
  }
}

export function adapterStatusLabel(status: string): string {
  switch (status.toLowerCase()) {
    case "up":
      return "已连接";
    case "disconnected":
      return "未连接";
    case "down":
      return "已断开";
    default:
      return status || "未知";
  }
}

export function cacheHitLabel(value: string | undefined): string {
  switch ((value ?? "").toLowerCase()) {
    case "fresh":
      return "缓存命中";
    case "stale":
      return "过期缓存";
    case "prefetch":
      return "预取命中";
    default:
      return value || "—";
  }
}

export function platformLabel(os: string | undefined): string {
  switch ((os ?? "").toLowerCase()) {
    case "windows":
      return "Windows";
    case "linux":
      return "Linux";
    case "darwin":
      return "macOS";
    default:
      return os || "—";
  }
}

export function autoStartMechanismLabel(mechanism: string | undefined): string {
  switch (mechanism) {
    case "service":
      return "系统服务";
    case "systemd":
      return "systemd";
    case "task":
      return "计划任务";
    default:
      return mechanism || "";
  }
}

export function serviceStateLabel(state: string, fallback: string): string {
  switch (state) {
    case "running":
      return "运行中";
    case "stopped":
      return "已停止";
    case "not_installed":
      return "未安装";
    default:
      return fallback || state;
  }
}

export const qtypeOptions = [
  { value: "all", label: "全部类型" },
  { value: "A", label: "A" },
  { value: "AAAA", label: "AAAA" },
  { value: "CNAME", label: "CNAME" },
  { value: "HTTPS", label: "HTTPS" },
  { value: "TXT", label: "TXT" },
  { value: "MX", label: "MX" },
  { value: "NS", label: "NS" },
  { value: "PTR", label: "PTR" },
  { value: "SRV", label: "SRV" },
];

export const statusOptions = [
  { value: "all", label: "全部状态" },
  { value: "allowed", label: "允许" },
  { value: "blocked", label: "拦截" },
  { value: "cached", label: "缓存" },
  { value: "stale", label: "过期缓存" },
  { value: "error", label: "失败" },
];
