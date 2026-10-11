/**
 * md-switch / checkbox 视觉状态安全回滚与值提取。
 */

export function extractSwitchValue(e: Event): boolean {
  const t = e.target as any;
  if (!t) return false;
  if ('selected' in t) return Boolean(t.selected);
  if ('checked' in t) return Boolean(t.checked);
  return false;
}

export function revertSwitch(e: Event, previous: boolean): void {
  const t = e.target as any;
  if (!t) return;
  if ('selected' in t) {
    t.selected = previous;
  } else if ('checked' in t) {
    t.checked = previous;
  }
}
