/** 日期时间与时长格式化工具（供各视图统一复用） */

function pad2(n: number): string {
  return n.toString().padStart(2, '0');
}

/** 时分秒，如 09:05:31 */
export function formatClockTime(timestampMs: number): string {
  const d = new Date(timestampMs);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/** 时分秒.毫秒，用于访问日志等高精度场景 */
export function formatClockTimeMs(timestamp: number): string {
  const d = new Date(timestamp);
  return `${formatClockTime(timestamp)}.${d.getMilliseconds().toString().padStart(3, '0')}`;
}

/** 月-日 时:分，如 08-14 21:07 */
export function formatMonthDayTime(ms: number): string {
  const d = new Date(ms);
  return `${d.getMonth() + 1}-${d.getDate()} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** 将秒数格式化为「X小时 Y分 / Y分 Z秒 / Z秒」 */
export function formatUptime(seconds: number): string {
  const sec = seconds || 0;
  const hours = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (hours > 0) return `${hours}小时 ${mins}分`;
  if (mins > 0) return `${mins}分 ${s}秒`;
  return `${s}秒`;
}
