/**
 * md-switch 视觉状态回滚。
 *
 * @material/web 的 md-switch 使用 `selected` 属性，而原生 input 使用 `checked`，
 * 这里统一处理，避免每个调用点重复判断。
 */

/** 操作失败时把开关视觉状态回滚到切换前 */
export function revertSwitch(e: Event, previous: boolean): void {
  const t = e.target as any;
  if ('selected' in t) {
    t.selected = previous;
  } else {
    t.checked = previous;
  }
}
