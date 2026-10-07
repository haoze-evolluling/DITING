<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { ipc } from './api/ipc';
import { themeManager } from './theme/dynamic-color';
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

const currentTab = ref<NavTab>('dashboard');
const isConnected = ref(false);
const isDark = ref(themeManager.isDark());
const showAlertModal = ref(false);

const navItems = [
  { id: 'dashboard' as NavTab, label: '总览大盘', icon: 'dashboard' },
  { id: 'adapters' as NavTab, label: '网卡接管', icon: 'adapters' },
  { id: 'upstream' as NavTab, label: '上游调度', icon: 'upstream' },
  { id: 'cache' as NavTab, label: '智能缓存', icon: 'cache' },
  { id: 'rules' as NavTab, label: '规则防护', icon: 'shield' },
  { id: 'logs' as NavTab, label: '实时日志', icon: 'logs' },
  { id: 'settings' as NavTab, label: '设置中心', icon: 'settings' },
];

let unsubConn: (() => void) | null = null;
let unsubTheme: (() => void) | null = null;

function toggleTheme() {
  const nextMode = isDark.value ? 'light' : 'dark';
  themeManager.setThemeMode(nextMode);
}

function handleNavigate(tab: string) {
  currentTab.value = tab as NavTab;
}

async function retryConnect() {
  showAlertModal.value = false;
  await ipc.checkHealth();
  ipc.reconnectWS();
}

onMounted(() => {
  ipc.connectWS();
  ipc.checkHealth();

  unsubConn = ipc.onConnectionChange((connected) => {
    isConnected.value = connected;
    if (!connected) {
      setTimeout(() => {
        if (!ipc.isConnected) {
          showAlertModal.value = true;
        }
      }, 2000);
    } else {
      showAlertModal.value = false;
    }
  });

  unsubTheme = themeManager.onChange(() => {
    isDark.value = themeManager.isDark();
  });
});

onUnmounted(() => {
  if (unsubConn) unsubConn();
  if (unsubTheme) unsubTheme();
});
</script>

<template>
  <div class="flex h-screen w-screen overflow-hidden bg-surface-base text-text-main font-sans antialiased select-none">
    <!-- M3 桌面端 Navigation Rail (左侧垂直导航轨) -->
    <nav class="w-20 md:w-24 shrink-0 flex flex-col items-center justify-between py-5 border-r border-surface-border bg-surface-card transition-colors z-20">
      <!-- 顶部 Logo & 品牌徽标 -->
      <div class="flex flex-col items-center gap-2">
        <div class="relative group cursor-pointer" @click="currentTab = 'dashboard'">
          <img
            src="./assets/images/logo-universal.png"
            alt="谛听 Logo"
            class="w-10 h-10 drop-shadow-sm transition-transform duration-200 group-hover:scale-105"
          />
          <span
            class="absolute -bottom-1 -right-1 flex h-3.5 w-3.5 rounded-full border-2 border-surface-card"
            :class="isConnected ? 'bg-status-success' : 'bg-status-error'"
            :title="isConnected ? '特权服务已连接' : '特权服务未连接'"
          />
        </div>
        <span class="text-[11px] font-bold tracking-tight text-text-main">谛听 DNS</span>
      </div>

      <!-- 导航项列表 (Navigation Rail Destination) -->
      <div class="flex flex-col items-center gap-2.5 my-auto w-full px-2">
        <button
          v-for="item in navItems"
          :key="item.id"
          @click="currentTab = item.id"
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
                ? 'bg-brand-container text-brand-primary shadow-2xs'
                : 'text-inherit',
            ]"
          >
            <M3Icon :name="item.icon" :size="20" />
          </div>
          <span class="text-[11px] mt-1 tracking-tight">{{ item.label }}</span>
        </button>
      </div>

      <!-- 底部辅助工具 (明暗切换与连接状态) -->
      <div class="flex flex-col items-center gap-3">
        <!-- 主题切换 -->
        <button
          @click="toggleTheme"
          class="flex items-center justify-center w-9 h-9 rounded-xl text-text-sub hover:text-text-main hover:bg-surface-hover transition-colors cursor-pointer"
          :title="isDark ? '切换浅色模式' : '切换深色模式'"
        >
          <M3Icon :name="isDark ? 'light_mode' : 'dark_mode'" :size="18" />
        </button>

        <!-- 设置快捷入口 -->
        <button
          @click="currentTab = 'settings'"
          class="flex items-center justify-center w-9 h-9 rounded-xl text-text-sub hover:text-text-main hover:bg-surface-hover transition-colors cursor-pointer"
          :class="{ 'text-brand-primary': currentTab === 'settings' }"
          title="系统与外观设置"
        >
          <M3Icon name="settings" :size="18" />
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
          <span class="text-xs text-text-sub">Windows 桌面客户端 v0.1.0</span>
        </div>

        <div class="flex items-center gap-3">
          <StatusBadge
            :status="isConnected ? 'active' : 'error'"
            :text="isConnected ? '特权服务 15353 在线' : '特权服务离线'"
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

    <!-- 特权服务未运行友好引导弹窗 (居中与现代圆角按钮) -->
    <AppModal
      :open="showAlertModal"
      @close="showAlertModal = false"
      type="alert"
    >
      <template #headline>
        <div class="flex items-center gap-2 text-status-error font-bold">
          <M3Icon name="warning" :size="22" />
          <span>未检测到特权服务运行</span>
        </div>
      </template>

      <div class="space-y-3 pt-1">
        <p class="text-xs text-text-sub leading-relaxed">
          谛听客户端需要后台特权服务 (<code>diting-service.exe</code>) 以管理员权限运行，以接管物理网卡 DNS 并监听 53 端口。请确认服务已启动或使用以下命令手动运行：
        </p>
        <div class="p-3 rounded-xl bg-surface-card-sub border border-surface-border font-mono text-xs text-text-main select-all">
          diting-service.exe -run
        </div>
      </div>

      <template #actions>
        <button
          @click="showAlertModal = false"
          class="px-4 py-2 rounded-xl text-xs font-semibold text-text-sub hover:text-text-main hover:bg-surface-hover transition-colors cursor-pointer"
        >
          稍后处理
        </button>
        <button
          @click="retryConnect"
          class="px-5 py-2 rounded-xl text-xs font-semibold text-white bg-brand-primary hover:bg-brand-primary-hover shadow-xs flex items-center gap-1.5 transition-all flex-shrink-0 cursor-pointer"
        >
          <M3Icon name="refresh" :size="15" />
          <span>重新尝试连接</span>
        </button>
      </template>
    </AppModal>
  </div>
</template>
