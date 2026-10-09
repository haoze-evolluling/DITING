import type { CoreServiceStatus } from './types';

// Wails 全局对象类型声明
declare global {
  interface Window {
    go?: {
      main?: {
        App?: {
          Greet?: (name: string) => Promise<string>;
          RunEmergencyRestore?: () => Promise<string>;
          IsAutoStartEnabled?: () => Promise<boolean>;
          SetAutoStart?: (enable: boolean) => Promise<boolean>;
          GetCoreServiceStatus?: () => Promise<CoreServiceStatus>;
          StartCoreService?: () => Promise<string>;
          StopCoreService?: () => Promise<string>;
          RestartCoreService?: () => Promise<string>;
          InstallCoreService?: () => Promise<string>;
          InstallAndStartCoreService?: () => Promise<string>;
          UninstallCoreService?: () => Promise<string>;
          ConfigureFirewallForLAN?: (enable: boolean) => Promise<string>;
        };
      };
    };
  }
}

export class NativeBridgeService {
  public isDesktopApp(): boolean {
    return typeof window !== 'undefined' && Boolean(window.go?.main?.App);
  }

  public async runNativeEmergencyRestore(): Promise<string> {
    if (window.go?.main?.App?.RunEmergencyRestore) {
      return await window.go.main.App.RunEmergencyRestore();
    }
    return 'Web 环境不支持原生底层 DNS 应急自愈，请在宿主机桌面端执行';
  }

  public async isAutoStartEnabled(): Promise<boolean> {
    if (window.go?.main?.App?.IsAutoStartEnabled) {
      try {
        return await window.go.main.App.IsAutoStartEnabled();
      } catch (e) {
        console.warn('获取开机自启状态失败:', e);
      }
    }
    return false;
  }

  public async setAutoStart(enable: boolean): Promise<boolean> {
    if (window.go?.main?.App?.SetAutoStart) {
      return await window.go.main.App.SetAutoStart(enable);
    }
    return enable;
  }

  public async getCoreServiceStatus(): Promise<CoreServiceStatus> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      const mockState = (window as any).__mockCoreServiceStatus || {
        installed: true,
        running: true,
        state: 'running',
        stateText: '运行中',
        executablePath: 'C:\\Program Files\\Diting\\谛听 DNS\\diting-service.exe',
        isElevated: false,
        canInstall: true,
        message: '核心服务正常运行中。',
      };
      return mockState;
    }

    if (window.go?.main?.App?.GetCoreServiceStatus) {
      try {
        const res = await window.go.main.App.GetCoreServiceStatus();
        return res as CoreServiceStatus;
      } catch (err: any) {
        console.warn('获取核心服务状态失败:', err);
      }
    }

    return {
      installed: false,
      running: false,
      state: 'unknown',
      stateText: '未知状态',
      executablePath: '',
      isElevated: false,
      canInstall: false,
      message: 'Web 浏览器环境，服务由宿主机后台守护进程运行。',
    };
  }

  public async startCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      if ((window as any).__mockCoreServiceStatus) {
        (window as any).__mockCoreServiceStatus.running = true;
        (window as any).__mockCoreServiceStatus.state = 'running';
        (window as any).__mockCoreServiceStatus.stateText = '运行中';
      }
      return '后台核心服务已成功启动！';
    }
    if (window.go?.main?.App?.StartCoreService) {
      return await window.go.main.App.StartCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持直接控制宿主机 Windows 系统服务启动');
  }

  public async stopCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      if ((window as any).__mockCoreServiceStatus) {
        (window as any).__mockCoreServiceStatus.running = false;
        (window as any).__mockCoreServiceStatus.state = 'stopped';
        (window as any).__mockCoreServiceStatus.stateText = '已停止';
      }
      return '后台核心服务已停止。';
    }
    if (window.go?.main?.App?.StopCoreService) {
      return await window.go.main.App.StopCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持直接控制宿主机 Windows 系统服务停止');
  }

  public async restartCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      return '后台核心服务已成功重启！';
    }
    if (window.go?.main?.App?.RestartCoreService) {
      return await window.go.main.App.RestartCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持直接重启宿主机 Windows 系统服务');
  }

  public async installCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      if ((window as any).__mockCoreServiceStatus) {
        (window as any).__mockCoreServiceStatus.installed = true;
        (window as any).__mockCoreServiceStatus.state = 'stopped';
        (window as any).__mockCoreServiceStatus.stateText = '已停止';
      }
      return '后台核心服务已成功安装！';
    }
    if (window.go?.main?.App?.InstallCoreService) {
      return await window.go.main.App.InstallCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持触发宿主机 Windows UAC 服务注册安装');
  }

  public async installAndStartCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      if ((window as any).__mockCoreServiceStatus) {
        (window as any).__mockCoreServiceStatus.installed = true;
        (window as any).__mockCoreServiceStatus.running = true;
        (window as any).__mockCoreServiceStatus.state = 'running';
        (window as any).__mockCoreServiceStatus.stateText = '运行中';
      }
      return '后台核心服务已成功安装并启动！';
    }
    if (window.go?.main?.App?.InstallAndStartCoreService) {
      return await window.go.main.App.InstallAndStartCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持一键安装并启动宿主机系统服务');
  }

  public async uninstallCoreService(): Promise<string> {
    if (typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('mock') === '1') {
      if ((window as any).__mockCoreServiceStatus) {
        (window as any).__mockCoreServiceStatus.installed = false;
        (window as any).__mockCoreServiceStatus.running = false;
        (window as any).__mockCoreServiceStatus.state = 'not_installed';
        (window as any).__mockCoreServiceStatus.stateText = '未安装';
      }
      return '后台核心服务已成功卸载。';
    }
    if (window.go?.main?.App?.UninstallCoreService) {
      return await window.go.main.App.UninstallCoreService();
    }
    throw new Error('当前环境为 Web 浏览器，不支持触发宿主机 Windows UAC 服务卸载');
  }
}

export const nativeBridge = new NativeBridgeService();
