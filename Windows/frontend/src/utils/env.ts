/** 运行环境判定：Wails 桌面客户端 还是 浏览器 Web 控制台 */

/** 是否运行在 Wails 桌面客户端（存在原生绑定） */
export function isDesktopApp(): boolean {
  return typeof window !== 'undefined' && Boolean(window.go?.main?.App);
}

/** 是否运行在浏览器 Web 控制台 */
export function isWebMode(): boolean {
  return !isDesktopApp();
}
