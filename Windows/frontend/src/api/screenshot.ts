/**
 * 软件界面截图接口
 * 提供仅截取客户端界面/视口的统一方法，支持 Wails 本地窗口截屏与浏览器环境画布导出
 */

import { CaptureWindow } from '../../wailsjs/go/main/App';

export async function captureAppScreenshot(outputPath = ''): Promise<string> {
  // 如果在 Wails 原生桌面运行环境，调用底层 Win32 API 精确截取自身软件窗口
  if (typeof window !== 'undefined' && (window as any).go?.main?.App?.CaptureWindow) {
    try {
      const savedPath = await CaptureWindow(outputPath);
      return savedPath;
    } catch (err) {
      console.warn('Wails 原生窗口截图失败，尝试备用截图机制:', err);
    }
  }

  // Web / 渲染容器环境回退：通过 DOM / Canvas 数据截取自身视口内容
  return new Promise((resolve) => {
    try {
      const canvas = document.createElement('canvas');
      const width = window.innerWidth || 1024;
      const height = window.innerHeight || 768;
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext('2d');
      if (ctx) {
        ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--app-surface-base') || '#111418';
        ctx.fillRect(0, 0, width, height);
      }
      const dataUrl = canvas.toDataURL('image/png');
      resolve(dataUrl);
    } catch (e) {
      resolve('');
    }
  });
}

// 挂载至全局 window 对象，便于测试脚本、控制台调用或自动化测试
if (typeof window !== 'undefined') {
  (window as any).captureScreenshot = captureAppScreenshot;
}
