import { ref } from 'vue';
import { ipc } from '../api/ipc';
import type { CoreServiceStatus } from '../api/types';

export type ServiceAction =
  | 'start'
  | 'stop'
  | 'restart'
  | 'install'
  | 'install_and_start'
  | 'uninstall';

const ACTION_LABELS: Record<ServiceAction, string> = {
  start: '启动服务',
  stop: '停止服务',
  restart: '重启服务',
  install: '安装服务',
  install_and_start: '安装并启动服务',
  uninstall: '卸载服务',
};

function isUACCancelled(err: any): boolean {
  const msg = err?.message || '';
  return msg.includes('取消') || msg.includes('canceled') || msg.includes('1223');
}

/**
 * 后台核心服务的状态查询与生命周期操作（含 UAC 取消提示与操作后状态刷新）。
 */
export function useServiceControl() {
  const status = ref<CoreServiceStatus | null>(null);
  const loading = ref(false);
  const operating = ref(false);
  const opMessage = ref('');
  const opError = ref('');

  async function fetchStatus() {
    loading.value = true;
    opError.value = '';
    try {
      status.value = await ipc.getCoreServiceStatus();
    } catch (err: any) {
      opError.value = err.message || '获取服务状态失败';
    } finally {
      loading.value = false;
    }
  }

  async function run(action: ServiceAction): Promise<void> {
    if (operating.value) return;
    operating.value = true;
    opMessage.value = '';
    opError.value = '';

    try {
      let msg = '';
      switch (action) {
        case 'start':
          msg = await ipc.startCoreService();
          break;
        case 'stop':
          msg = await ipc.stopCoreService();
          break;
        case 'restart':
          msg = await ipc.restartCoreService();
          break;
        case 'install':
          msg = await ipc.installCoreService();
          break;
        case 'install_and_start':
          msg = await ipc.installAndStartCoreService();
          break;
        case 'uninstall':
          msg = await ipc.uninstallCoreService();
          break;
      }
      opMessage.value = msg || `${ACTION_LABELS[action]}成功`;
      await fetchStatus();
      await ipc.checkHealth();
    } catch (err: any) {
      opError.value = isUACCancelled(err)
        ? '管理员权限授权已取消，该项操作需要管理员特权。'
        : err.message || `${ACTION_LABELS[action]}失败`;
    } finally {
      operating.value = false;
    }
  }

  return { status, loading, operating, opMessage, opError, fetchStatus, run };
}
