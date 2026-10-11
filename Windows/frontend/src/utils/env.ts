/** 运行环境判定：Wails 桌面客户端还是浏览器 Web 控制台 */

export function isDesktopApp(): boolean {
  return typeof window !== 'undefined' && Boolean(window.go?.main?.App);
}

export function isWebMode(): boolean {
  return !isDesktopApp();
}
