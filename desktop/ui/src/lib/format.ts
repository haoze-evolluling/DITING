const integer = new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 0 });
const decimal = new Intl.NumberFormat("zh-CN", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return integer.format(value);
}

export function formatCompact(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  if (Math.abs(value) < 10_000) return integer.format(value);
  if (Math.abs(value) < 1_000_000) return `${decimal.format(value / 1_000)}k`;
  return `${decimal.format(value / 1_000_000)}M`;
}

/** Input is a ratio in the 0–1 range. */
export function formatRatio(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return `${(value * 100).toFixed(1)}%`;
}

/** Input is already expressed as a percentage in the 0–100 range. */
export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return `${value.toFixed(1)}%`;
}

export function formatLatency(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  if (value <= 0) return "—";
  if (value >= 1000) return `${(value / 1000).toFixed(2)} s`;
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ms`;
}

export function formatUptime(seconds: number | null | undefined): string {
  if (!seconds || seconds < 0) return "—";
  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  if (days > 0) return `${days} 天 ${hours} 小时`;
  if (hours > 0) return `${hours} 小时 ${minutes} 分`;
  return `${Math.max(minutes, 1)} 分钟`;
}

function pad(value: number, length = 2): string {
  return String(value).padStart(length, "0");
}

export function formatClock(ts: number): string {
  if (!ts) return "—";
  const date = new Date(ts);
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

export function formatDateTime(ts: number): string {
  if (!ts) return "—";
  const date = new Date(ts);
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${formatClock(ts)}`;
}

export function displayDomain(value: string): string {
  return value.endsWith(".") ? value.slice(0, -1) : value;
}

export function formatHour(ms: number): string {
  const date = new Date(ms);
  return `${pad(date.getHours())}:00`;
}

export function formatRelative(ts: number): string {
  if (!ts) return "—";
  const delta = Date.now() - ts;
  if (delta < 15_000) return "刚刚";
  if (delta < 60_000) return `${Math.floor(delta / 1000)} 秒前`;
  if (delta < 3_600_000) return `${Math.floor(delta / 60_000)} 分钟前`;
  if (delta < 86_400_000) return `${Math.floor(delta / 3_600_000)} 小时前`;
  return formatDateTime(ts);
}

export function formatUnixSeconds(seconds: number): string {
  if (!seconds) return "—";
  return formatDateTime(seconds * 1000);
}

export function shortId(value: string, head = 8, tail = 6): string {
  if (!value || value.length <= head + tail + 1) return value;
  return `${value.slice(0, head)}…${value.slice(-tail)}`;
}

export function hourRangeLabel(points: { hourMs: number }[]): string {
  if (points.length === 0) return "过去 24 小时";
  const first = new Date(points[0].hourMs);
  const last = new Date(points[points.length - 1].hourMs);
  return `${pad(first.getMonth() + 1)}-${pad(first.getDate())} ${pad(first.getHours())}:00 至 ${pad(
    last.getDate(),
  )} ${pad(last.getHours())}:00`;
}
