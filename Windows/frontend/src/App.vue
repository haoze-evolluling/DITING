<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { ipc } from './api/ipc';
import { themeManager } from './theme/theme';
import { NAV_ITEMS, isValidTab, type NavTab } from './constants/navigation';
import { isWebMode } from './utils/env';
import M3Icon from './components/M3Icon.vue';
import NavItem from './components/NavItem.vue';
import StatusBadge from './components/StatusBadge.vue';
import ServiceAlertModal from './components/ServiceAlertModal.vue';
import LoginModal from './components/LoginModal.vue';
import DashboardView from './views/DashboardView.vue';
import AdaptersView from './views/AdaptersView.vue';
import UpstreamView from './views/UpstreamView.vue';
import LogsView from './views/LogsView.vue';
import SettingsView from './views/SettingsView.vue';
import CacheView from './views/CacheView.vue';
import RulesView from './views/RulesView.vue';

const appVersion = __APP_VERSION__;
const navItems = NAV_ITEMS;
const currentTab = ref<NavTab>('dashboard');
const isConnected = ref(false);
const showAlertModal = ref(false);

// Web 远程管理与用户态
const webMode = isWebMode();
const currentUser = ref(localStorage.getItem('diting_session_user') || '');
const showAuthModal = ref(false);
const authModalMode = ref<'login' | 'setup'>('login');

let unsubConn: (() => void) | null = null;
let unsubAuth: (() => void) | null = null;

function parseRoute() {
  try {
    const url = new URL(window.location.href);
    const hash = url.hash.replace(/^#\/?/, '').split('?')[0].toLowerCase();
    const tabParam = (url.searchParams.get('tab') || hash).toLowerCase();
    if (isValidTab(tabParam)) {
      currentTab.value = tabParam;
    }
    const themeParam = url.searchParams.get('theme');
    if (themeParam === 'light' || themeParam === 'dark' || themeParam === 'system') {
      themeManager.setThemeMode(themeParam);
    }
    if (url.searchParams.has('modal')) {
      showAlertModal.value = url.searchParams.get('modal') === 'alert';
    }
  } catch {}
}

function handleNavigate(tab: NavTab) {
  currentTab.value = tab;
  try {
    window.location.hash = '#' + tab;
  } catch {}
}

async function checkWebAuth() {
  if (!webMode) return;
  try {
    const status = await ipc.getAuthStatus();
    if (!status.initialized) {
      authModalMode.value = 'setup';
      showAuthModal.value = true;
    } else {
      const token = localStorage.getItem('diting_session_token');
      if (!token) {
        authModalMode.value = 'login';
        showAuthModal.value = true;
      } else {
        currentUser.value = status.username || 'admin';
      }
    }
  } catch (err: any) {
    if (err.message && (err.message.includes('未授权') || err.message.includes('401'))) {
      authModalMode.value = 'login';
      showAuthModal.value = true;
    }
  }
}

async function handleLogout() {
  await ipc.logout();
  currentUser.value = '';
  authModalMode.value = 'login';
  showAuthModal.value = true;
}

function handleAuthSuccess() {
  showAuthModal.value = false;
  currentUser.value = localStorage.getItem('diting_session_user') || 'admin';
  ipc.reconnectWS();
  ipc.checkHealth();
}

onMounted(() => {
  parseRoute();
  window.addEventListener('hashchange', parseRoute);

  checkWebAuth();
  ipc.connectWS();
  ipc.checkHealth();

  unsubAuth = ipc.onAuthRequired((required) => {
    if (webMode && required) {
      authModalMode.value = 'login';
      showAuthModal.value = true;
    }
  });

  unsubConn = ipc.onConnectionChange((connected) => {
    isConnected.value = connected;
    const url = new URL(window.location.href);
    const suppressAlert = url.searchParams.has('noalert');
    if (!connected && !suppressAlert && !webMode) {
      setTimeout(() => {
        const currentUrl = new URL(window.location.href);
        if (!ipc.isConnected && !currentUrl.searchParams.has('noalert')) {
          showAlertModal.value = true;
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
  if (unsubAuth) unsubAuth();
});
</script>

<template>
  <div class="flex h-screen w-screen overflow-hidden bg-surface-base text-text-main font-sans antialiased select-none">
    <!-- 桌面端 M3 Navigation Rail (左侧垂直导航轨，中大屏展示) -->
    <nav class="hidden md:flex w-20 md:w-24 shrink-0 flex-col items-center py-6 border-r border-surface-border bg-surface-card transition-colors z-20">
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

      <!-- 导航项列表 -->
      <div class="flex flex-col items-center gap-2.5 my-auto w-full px-2">
        <NavItem
          v-for="item in navItems"
          :key="item.id"
          :id="item.id"
          :label="item.label"
          :icon="item.icon"
          :active="currentTab === item.id"
          @navigate="handleNavigate"
        />
      </div>
    </nav>

    <!-- 移动端底部导航栏 (手机小屏自适应展示) -->
    <nav class="md:hidden fixed bottom-0 left-0 right-0 h-16 z-30 bg-surface-card/95 backdrop-blur-md border-t border-surface-border flex items-center justify-around px-1 transition-colors">
      <NavItem
        v-for="item in navItems"
        :key="item.id"
        :id="item.id"
        :label="item.label"
        :icon="item.icon"
        :active="currentTab === item.id"
        compact
        @navigate="handleNavigate"
      />
    </nav>

    <!-- 右侧主视口区域 (Main Content Area) -->
    <main class="flex-1 flex flex-col h-full overflow-hidden bg-surface-base">
      <!-- 顶栏状态条 (Top Bar) -->
      <header class="h-14 shrink-0 flex items-center justify-between px-4 sm:px-8 border-b border-surface-border bg-surface-card/80 backdrop-blur-md transition-colors">
        <div class="flex items-center gap-2 sm:gap-3 min-w-0">
          <span class="text-sm font-bold text-text-main truncate">
            {{ navItems.find(i => i.id === currentTab)?.label }}
          </span>
          <span class="text-xs text-text-muted">|</span>
          <span class="text-xs text-text-sub truncate hidden sm:inline">
            {{ webMode ? '局域网 Web 控制台' : `Windows 桌面客户端 v${appVersion}` }}
          </span>
        </div>

        <div class="flex items-center gap-2 sm:gap-3 shrink-0">
          <!-- 用户态与登出 -->
          <div v-if="currentUser" class="flex items-center gap-2">
            <span class="text-xs font-semibold text-text-sub hidden sm:inline">
              <span class="text-text-muted">管理员:</span> {{ currentUser }}
            </span>
            <button
              v-if="webMode"
              type="button"
              @click="handleLogout"
              class="app-btn-secondary app-btn-compact text-xs"
              title="退出当前登录会话"
            >
              <M3Icon name="logout" :size="14" />
              <span class="hidden sm:inline">退出</span>
            </button>
          </div>

          <StatusBadge
            :status="isConnected ? 'active' : 'error'"
            :text="isConnected ? '服务运行中' : '服务未连接'"
            :pulse="isConnected"
            size="sm"
          />
        </div>
      </header>

      <!-- 视图容器 (Scrollable View Container，移动端增加底部安全间距) -->
      <div class="flex-1 overflow-y-auto px-4 sm:px-8 py-4 sm:py-6 pb-20 md:pb-6">
        <DashboardView v-if="currentTab === 'dashboard'" @navigate="handleNavigate" />
        <AdaptersView v-else-if="currentTab === 'adapters'" />
        <UpstreamView v-else-if="currentTab === 'upstream'" />
        <CacheView v-else-if="currentTab === 'cache'" />
        <RulesView v-else-if="currentTab === 'rules'" />
        <LogsView v-else-if="currentTab === 'logs'" />
        <SettingsView v-else-if="currentTab === 'settings'" />
      </div>
    </main>

    <!-- 后台核心服务管理弹窗 (桌面端异常引导) -->
    <ServiceAlertModal
      :open="showAlertModal"
      @close="showAlertModal = false"
      @connected="isConnected = true"
    />

    <!-- Web 管理员登录与首次设置向导弹窗 -->
    <LoginModal
      :open="showAuthModal"
      :mode="authModalMode"
      :force-modal="true"
      @close="showAuthModal = false"
      @success="handleAuthSuccess"
    />
  </div>
</template>
