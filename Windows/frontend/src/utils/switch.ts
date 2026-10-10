/**
 * md-switch 事件工具。
 *
 * @material/web 的 md-switch 使用 `selected` 属性，而部分版本/原生 input 使用 `checked`，
 * 这里统一读取与回滚，避免每个调用点重复判断。
 */

/** 读取开关切换后的目标值 */
export function switchValue(e: Event, fallback = false): boolean {
  const t = e.target as any;
  return Boolean(t.selected ?? t.checked ?? fallback);
}

/** 操作失败时把开关视觉状态回滚到切换前 */
export function revertSwitch(e: Event, previous: boolean): void {
  const t = e.target as any;
  if ('selected' in t) {
    t.selected = previous;
  } else {
    t.checked = previous;
  }
}
