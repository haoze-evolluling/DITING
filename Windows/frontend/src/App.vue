<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from 'vue';
import { ipc } from './api/ipc';
import { themeManager } from './theme/dynamic-color';
import type { CoreServiceStatus } from './api/types';
import M3Icon from './components/M3Icon.vue';
import StatusBadge from './components/StatusBadge.vue';
import AppModal from './components/AppModal.vue';
import DashboardView from './views/DashboardView.vue';
import AdaptersView from './views/AdaptersView.vue';
import UpstreamView from './views/UpstreamView.vue';
import LogsView from './views/LogsView.vue';
import SettingsView from './views/SettingsView.vue';
import CacheView from './views/CacheView.vue';
import RulesView from './views/RulesView.vue';

type NavTab = 'dashboard' | 'adapters' | 'upstream' | 'cache' | 'rules' | 'logs' | 'settings';

const appVersion = __APP_VERSION__;
const currentTab = ref<NavTab>('dashboard');
const isConnected = ref(false);
const showAlertModal = ref(false);

// 后台核心服务管理状态
const coreServiceStatus = ref<CoreServiceStatus | null>(null);
const isStatusLoading = ref(false);
const serviceOperating = ref(false);
const serviceOpText = ref('');
const serviceOpError = ref('');

const navItems = [
  { id: 'dashboard' as NavTab, label: '运行总览', icon: 'dashboard' },
  { id: 'adapters' as NavTab, label: '网络接管', icon: 'adapters' },
  { id: 'upstream' as NavTab, label: 'DNS 服务', icon: 'upstream' },
  { id: 'cache' as NavTab, label: '解析加速', icon: 'cache' },
  { id: 'rules' as NavTab, label: '规则拦截', icon: 'shield' },
  { id: 'logs' as NavTab, label: '访问日志', icon: 'logs' },
  { id: 'settings' as NavTab, label: '设置中心', icon: 'settings' },
];

let unsubConn: (() => void) | null = null;

async function loadCoreServiceStatus() {
  isStatusLoading.value = true;
  try {
    coreServiceStatus.value = await ipc.getCoreServiceStatus();
  } catch (err: any) {
    console.warn('获取核心服务状态失败:', err);
  } finally {
    isStatusLoading.value = false;
  }
}

function parseRoute() {
  try {
    const url = new URL(window.location.href);
    const hash = url.hash.replace(/^#\/?/, '').split('?')[0].toLowerCase();
    const tabParam = (url.searchParams.get('tab') || hash).toLowerCase();
    const validTabs: NavTab[] = ['dashboard', 'adapters', 'upstream', 'cache', 'rules', 'logs', 'settings'];
    if (validTabs.includes(tabParam as NavTab)) {
      currentTab.value = tabParam as NavTab;
    }
    const themeParam = url.searchParams.get('theme');
    if (themeParam === 'light' || themeParam === 'dark' || themeParam === 'system') {
      themeManager.setThemeMode(themeParam);
    }
    if (url.searchParams.has('modal')) {
      showAlertModal.value = url.searchParams.get('modal') === 'alert';
    }
    if (url.searchParams.get('mock') === '1') {
      const svcParam = url.searchParams.get('service');
      if (svcParam === 'not_installed') {
        (window as any).__mockCoreServiceStatus = {
          installed: false,
          running: false,
          state: 'not_installed',
          stateText: '未安装',
          executablePath: 'C:\\Program Files\\Diting\\谛听 DNS\\diting-service.exe',
          isElevated: false,
          canInstall: true,
          message: '后台核心服务尚未安装到系统中。',
        };
        isConnected.value = false;
        if (!url.searchParams.has('modal')) showAlertModal.value = true;
      } else if (svcParam === 'stopped') {
        (window as any).__mockCoreServiceStatus = {
          installed: true,
          running: false,
          state: 'stopped',
          stateText: '已停止',
          executablePath: 'C:\\Program Files\\Diting\\谛听 DNS\\diting-service.exe',
          isElevated: false,
          canInstall: true,
          message: '核心服务已安装，当前处于停止状态。',
        };
        isConnected.value = false;
        if (!url.searchParams.has('modal')) showAlertModal.value = true;
      } else {
        isConnected.value = true;
        if (!url.searchParams.has('modal')) {
          showAlertModal.value = false;
        }
      }
    }
  } catch (e) {
    // ignore URL parse errors
  }
}

function handleNavigate(tab: string) {
  currentTab.value = tab as NavTab;
  try {
    window.location.hash = '#' + tab;
  } catch (_) {}
}

const isRetrying = ref(false);

async function retryConnect(): Promise<boolean> {
  if (isRetrying.value) return false;
  isRetrying.value = true;
  try {
    const healthy = await ipc.checkHealth();
    ipc.reconnectWS();
    if (healthy) {
      showAlertModal.value = false;
      return true;
    }
    await loadCoreServiceStatus();
    return false;
  } finally {
    isRetrying.value = false;
  }
}

async function handleInstallService() {
  if (serviceOperating.value) return;
  serviceOperating.value = true;
  serviceOpText.value = '正在请求系统授权并安装服务...';
  serviceOpError.value = '';

  try {
    await ipc.installCoreService();
    serviceOpText.value = '服务安装成功！正在刷新状态...';
    await new Promise((r) => setTimeout(r, 800));
    await loadCoreServiceStatus();
  } catch (err: any) {
    if (err.message?.includes('取消') || err.message?.includes('canceled') || err.message?.includes('1223')) {
      serviceOpError.value = '管理员权限授权已取消。安装系统服务需要管理员特权。';
    } else {
      serviceOpError.value = err.message || '安装服务失败，请重试';
    }
  } finally {
    serviceOperating.value = false;
  }
}

async function handleInstallAndStart() {
  if (serviceOperating.value) return;
  serviceOperating.value = true;
  serviceOpText.value = '正在请求系统授权并安装服务...';
  serviceOpError.value = '';

  try {
    await ipc.installAndStartCoreService();
    serviceOpText.value = '安装完成，正在建立服务通信...';
    await new Promise((r) => setTimeout(r, 1500));
    const healthy = await retryConnect();
    if (healthy) {
      showAlertModal.value = false;
    } else {
      await loadCoreServiceStatus();
    }
  } catch (err: any) {
    if (err.message?.includes('取消') || err.message?.includes('canceled') || err.message?.includes('1223')) {
      serviceOpError.value = '管理员权限授权已取消。安装系统服务需要管理员特权。';
    } else {
      serviceOpError.value = err.message || '安装服务失败，请重试';
    }
  } finally {
    serviceOperating.value = false;
  }
}

async function handleStartService() {
  if (serviceOperating.value) return;
  serviceOperating.value = true;
  serviceOpText.value = '正在请求系统授权并启动服务...';
  serviceOpError.value = '';

  try {
    await ipc.startCoreService();
    serviceOpText.value = '启动完成，正在连接后台服务...';
    await new Promise((r) => setTimeout(r, 1200));
    const healthy = await retryConnect();
    if (healthy) {
      showAlertModal.value = false;
    } else {
      await loadCoreServiceStatus();
    }
  } catch (err: any) {
    if (err.message?.includes('取消') || err.message?.includes('canceled') || err.message?.includes('1223')) {
      serviceOpError.value = '管理员权限授权已取消。启动系统服务需要管理员特权。';
    } else {
      serviceOpError.value = err.message || '启动服务失败，请重试';
    }
  } finally {
    serviceOperating.value = false;
  }
}

async function handleRestartService() {
  if (serviceOperating.value) return;
  serviceOperating.value = true;
  serviceOpText.value = '正在重启后台核心服务...';
  serviceOpError.value = '';

  try {
    await ipc.restartCoreService();
    serviceOpText.value = '重启成功，正在重新连接...';
    await new Promise((r) => setTimeout(r, 1500));
    await retryConnect();
  } catch (err: any) {
    serviceOpError.value = err.message || '重启服务失败';
  } finally {
    serviceOperating.value = false;
  }
}

watch(showAlertModal, (open) => {
  if (open) {
    serviceOpError.value = '';
    loadCoreServiceStatus();
  }
});

onMounted(() => {
  parseRoute();
  window.addEventListener('hashchange', parseRoute);

  loadCoreServiceStatus();
  ipc.connectWS();
  ipc.checkHealth();

  unsubConn = ipc.onConnectionChange((connected) => {
    isConnected.value = connected;
    const url = new URL(window.location.href);
    const suppressAlert = url.searchParams.has('noalert');
    if (!connected && !suppressAlert) {
      setTimeout(() => {
        const currentUrl = new URL(window.location.href);
        if (!ipc.isConnected && !currentUrl.searchParams.has('noalert')) {
          showAlertModal.value = true;
          loadCoreServiceStatus();
        }
      }, 2000);
    } else if (connected) {
      showAlertModal.value = false;
    }
  });
});

onUnmounted(() => {
  window.removeEventListener('hashchange', parseRoute);
  if (unsubConn) unsubConn();
});
</script>

<template>
  <div class="flex h-screen w-screen overflow-hidden bg-surface-base text-text-main font-sans antialiased select-none">
    <!-- M3 桌面端 Navigation Rail (左侧垂直导航轨) -->
    <nav class="w-20 md:w-24 shrink-0 flex flex-col items-center py-6 border-r border-surface-border bg-surface-card transition-colors z-20">
      <!-- 顶部 Logo & 品牌徽标 -->
      <div class="flex flex-col items-center gap-2">
        <div class="relative group cursor-pointer" @click="handleNavigate('dashboard')">
          <img
            src="./assets/images/logo-universal.png"
            alt="谛听 Logo"
            class="w-10 h-10 drop-shadow-sm transition-transform duration-200 group-hover:scale-105"
          />
          <span
            class="absolute -bottom-1 -right-1 flex h-3.5 w-3.5 rounded-full border-2 border-surface-card"
            :class="isConnected ? 'bg-status-success' : 'bg-status-error'"
            :title="isConnected ? '后台服务已连接' : '后台服务未连接'"
          />
        </div>
        <span class="text-[11px] font-bold tracking-tight text-text-main">谛听 DNS</span>
      </div>

      <!-- 导航项列表 (Navigation Rail Destination) -->
      <div class="flex flex-col items-center gap-2.5 my-auto w-full px-2">
        <button
          v-for="item in navItems"
          :key="item.id"
          @click="handleNavigate(item.id)"
          class="group relative flex flex-col items-center justify-center w-full py-2 rounded-2xl transition-all duration-200 cursor-pointer"
          :class="[
            currentTab === item.id
              ? 'text-brand-primary font-bold'
              : 'text-text-sub hover:text-text-main hover:bg-surface-hover',
          ]"
        >
          <!-- M3 活动指示气泡 (Active Indicator) -->
          <div
            class="flex items-center justify-center w-14 h-8 rounded-full transition-all duration-200"
            :class="[
              currentTab === item.id
                ? 'bg-brand-container text-brand-on-container shadow-2xs'
                : 'text-inherit',
            ]"
          >
            <M3Icon :name="item.icon" :size="20" />
          </div>
          <span class="text-[11px] mt-1 tracking-tight">{{ item.label }}</span>
        </button>
      </div>
    </nav>

    <!-- 右侧主视口区域 (Main Content Area) -->
    <main class="flex-1 flex flex-col h-full overflow-hidden bg-surface-base">
      <!-- 顶栏状态条 (Top Bar) -->
      <header class="h-14 shrink-0 flex items-center justify-between px-8 border-b border-surface-border bg-surface-card/80 backdrop-blur-md transition-colors">
        <div class="flex items-center gap-3">
          <span class="text-sm font-bold text-text-main">
            {{ navItems.find(i => i.id === currentTab)?.label }}
          </span>
          <span class="text-xs text-text-muted">|</span>
          <span class="text-xs text-text-sub">Windows 桌面客户端 v{{ appVersion }}</span>
        </div>

        <div class="flex items-center gap-3">
          <StatusBadge
            :status="isConnected ? 'active' : 'error'"
            :text="isConnected ? '后台服务运行中' : '后台服务未连接'"
            :pulse="isConnected"
            size="sm"
          />
        </div>
      </header>

      <!-- 视图容器 (Scrollable View Container) -->
      <div class="flex-1 overflow-y-auto px-8 py-6">
        <DashboardView v-if="currentTab === 'dashboard'" @navigate="handleNavigate" />
        <AdaptersView v-else-if="currentTab === 'adapters'" />
        <UpstreamView v-else-if="currentTab === 'upstream'" />
        <CacheView v-else-if="currentTab === 'cache'" />
        <RulesView v-else-if="currentTab === 'rules'" />
        <LogsView v-else-if="currentTab === 'logs'" />
        <SettingsView v-else-if="currentTab === 'settings'" />
      </div>
    </main>

    <!-- 后台核心服务管理与引导弹窗 -->
    <AppModal
      :open="showAlertModal"
      @close="showAlertModal = false"
      type="alert"
    >
      <template #headline>
        <div
          class="flex items-center gap-2 font-bold"
          :class="
            isStatusLoading
              ? 'text-brand-primary'
              : coreServiceStatus?.installed
              ? 'text-status-warning'
              : 'text-status-error'
          "
        >
          <M3Icon :name="isStatusLoading ? 'sync' : 'warning'" :size="22" :class="isStatusLoading ? 'animate-spin' : ''" />
          <span>
            {{
              isStatusLoading
                ? '正在检测后台核心服务...'
                : !coreServiceStatus || !coreServiceStatus.installed
                ? '未安装后台核心服务'
                : coreServiceStatus.running
                ? '后台核心服务未连接'
                : '后台核心服务未启动'
            }}
          </span>
        </div>
      </template>

      <div class="space-y-3 pt-1">
        <!-- 服务状态指示条 -->
        <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border">
          <div class="flex items-center gap-2">
            <span class="text-xs font-semibold text-text-sub">当前服务状态:</span>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-bold"
              :class="[
                isStatusLoading
                  ? 'bg-brand-container text-brand-primary'
                  : coreServiceStatus?.installed && coreServiceStatus?.running
                  ? 'bg-status-success-bg text-status-success'
                  : coreServiceStatus?.installed
                  ? 'bg-status-warning-bg text-status-warning'
                  : 'bg-status-error-bg text-status-error'
              ]"
            >
              {{ isStatusLoading ? '检测中...' : (coreServiceStatus?.stateText || '未知状态') }}
            </span>
          </div>
          <span class="text-[11px] text-text-muted">
            {{ coreServiceStatus?.isElevated ? '管理员特权模式' : '按需请求系统权限' }}
          </span>
        </div>

        <!-- 场景描述 -->
        <!-- 正在加载中 -->
        <div v-if="isStatusLoading" class="p-4 flex flex-col items-center justify-center gap-2 text-xs text-text-sub">
          <M3Icon name="sync" :size="20" class="animate-spin text-brand-primary" />
          <span>正在与系统服务管理器通讯以确认核心服务状态...</span>
        </div>

        <!-- 场景1: 未安装服务 -->
        <div v-else-if="!coreServiceStatus || !coreServiceStatus.installed" class="space-y-2 text-xs text-text-sub leading-relaxed">
          <p>
            检测到当前 Windows 系统尚未安装谛听核心特权服务组件。
          </p>
          <p>
            核心服务负责双栈物理网卡 DNS 安全接管与多协议上游转发。点击下方<b>“安装服务”</b>或<b>“安装并启动服务”</b>，客户端将自动向系统注册服务并按需申请管理员权限，降低手动部署门槛。
          </p>
          <div v-if="coreServiceStatus?.executablePath" class="text-[11px] font-mono text-text-muted truncate" :title="coreServiceStatus.executablePath">
            组件位置: {{ coreServiceStatus.executablePath }}
          </div>
          <div v-if="coreServiceStatus && !coreServiceStatus.canInstall" class="p-2.5 rounded-lg bg-status-error-bg text-status-error border border-status-error/30 text-xs">
            未在程序目录找到 diting-service.exe，请检查程序安装是否完整。
          </div>
        </div>

        <!-- 场景2: 服务已安装但已停止 -->
        <div v-else-if="!coreServiceStatus.running" class="space-y-2 text-xs text-text-sub leading-relaxed">
          <p>
            后台核心服务已向系统注册，但当前处于<b>停止状态</b>。
          </p>
          <p>
            点击下方<b>“启动服务”</b>即可直接恢复网络加速与防护，系统将在需要时按需申请系统权限，无需在控制台输入任何指令。若服务配置损坏，也可点击“重新安装服务”。
          </p>
        </div>

        <!-- 场景3: 服务运行中但 IPC 未连接 -->
        <div v-else class="space-y-2 text-xs text-text-sub leading-relaxed">
          <p>
            核心服务进程已在系统中运行，但客户端尚未成功建立通信。可能服务正在启动初始化中，或者本地端口被占用。
          </p>
          <p>
            您可以点击“重新连接”尝试握手，或点击“重启服务”刷新服务状态。
          </p>
        </div>

        <!-- 操作中的加载动画反馈 -->
        <div
          v-if="serviceOperating"
          class="p-2.5 rounded-lg bg-brand-container text-brand-primary border border-brand-primary/20 text-xs flex items-center gap-2"
        >
          <M3Icon name="refresh" :size="15" class="animate-spin" />
          <span>{{ serviceOpText }}</span>
        </div>

        <!-- 操作失败/取消提示 -->
        <div
          v-if="serviceOpError"
          class="p-2.5 rounded-lg bg-status-error-bg text-status-error border border-status-error/30 text-xs flex items-center gap-2"
        >
          <M3Icon name="error" :size="15" />
          <span>{{ serviceOpError }}</span>
        </div>
      </div>

      <template #actions>
        <button
          @click="showAlertModal = false"
          :disabled="serviceOperating"
          class="app-btn-secondary"
        >
          稍后处理
        </button>

        <!-- 加载状态中 -->
        <template v-if="isStatusLoading">
          <button disabled class="app-btn-primary opacity-50 cursor-not-allowed">
            <M3Icon name="sync" :size="16" class="animate-spin" />
            <span>检测中...</span>
          </button>
        </template>

        <!-- 场景1: 未安装 -> 提供“安装服务”与“安装并启动服务” -->
        <template v-else-if="!coreServiceStatus || !coreServiceStatus.installed">
          <button
            @click="handleInstallService"
            :disabled="serviceOperating || !(coreServiceStatus?.canInstall)"
            class="app-btn-secondary"
            title="仅向系统注册 Windows 服务"
          >
            <M3Icon name="add" :size="16" />
            <span>安装服务</span>
          </button>
          <button
            @click="handleInstallAndStart"
            :disabled="serviceOperating || !(coreServiceStatus?.canInstall)"
            class="app-btn-primary"
            title="一键注册并启动后台核心服务"
          >
            <M3Icon name="bolt" :size="16" />
            <span>{{ serviceOperating ? '正在处理...' : '安装并启动服务' }}</span>
          </button>
        </template>

        <!-- 场景2: 已安装但已停止 -> 提供“重新安装服务”与“启动服务” -->
        <template v-else-if="!coreServiceStatus.running">
          <button
            @click="handleInstallService"
            :disabled="serviceOperating || !(coreServiceStatus?.canInstall)"
            class="app-btn-secondary"
            title="重新注册或修复 Windows 服务"
          >
            <M3Icon name="sync" :size="16" />
            <span>重新安装服务</span>
          </button>
          <button
            @click="handleStartService"
            :disabled="serviceOperating"
            class="app-btn-primary"
            title="启动后台核心特权服务"
          >
            <M3Icon name="play_arrow" :size="16" />
            <span>{{ serviceOperating ? '正在启动...' : '启动服务' }}</span>
          </button>
        </template>

        <!-- 场景3: 运行中未连接 -> 重启服务 + 重新尝试连接 -->
        <template v-else>
          <button
            @click="handleRestartService"
            :disabled="serviceOperating"
            class="app-btn-secondary"
          >
            <M3Icon name="refresh" :size="16" :class="serviceOperating ? 'animate-spin' : ''" />
            <span>重启服务</span>
          </button>
          <button
            @click="retryConnect"
            :disabled="isRetrying || serviceOperating"
            class="app-btn-primary"
          >
            <M3Icon name="refresh" :size="16" :class="isRetrying ? 'animate-spin' : ''" />
            <span>{{ isRetrying ? '正在连接...' : '重新尝试连接' }}</span>
          </button>
        </template>
      </template>
    </AppModal>
  </div>
</template>
