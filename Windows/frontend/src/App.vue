<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { ipc } from './api/ipc';
import { themeManager } from './theme/theme';
import { NAV_ITEMS, normalizeTab, type NavTab } from './constants/navigation';
import { isWebMode } from './utils/env';
import M3Icon from './components/M3Icon.vue';
import NavItem from './components/NavItem.vue';
import StatusBadge from './components/StatusBadge.vue';
import ServiceAlertModal from './components/ServiceAlertModal.vue';
import LoginModal from './components/LoginModal.vue';
import OverviewView from './views/OverviewView.vue';
import NetworkView from './views/NetworkView.vue';
import AccelView from './views/AccelView.vue';
import RulesView from './views/RulesView.vue';
import SystemView from './views/SystemView.vue';

const appVersion = __APP_VERSION__;
const navItems = NAV_ITEMS;
const currentTab = ref<NavTab>('overview');
const currentSub = ref<string>('');
const isConnected = ref(false);
const showAlertModal = ref(false);

// 宽屏（≥1024）展示文本侧栏，中屏（768–1024）折叠为图标栏
const wideSidebar = ref(true);
let mql: MediaQueryList | null = null;

const currentNav = computed(() => navItems.find((i) => i.id === currentTab.value));

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
    const hashParts = url.hash.replace(/^#\/?/, '').split('/');
    const hashTab = (hashParts[0] || '').split('?')[0];
    const rawTab = (url.searchParams.get('tab') || hashTab || '').toLowerCase();
    const tab = normalizeTab(rawTab);
    if (tab) {
      currentTab.value = tab;
    }
    // 子页签：查询参数优先，其次 hash 第二段；旧 logs 标签落到实时查询
    const subParam = url.searchParams.get('sub') || hashParts[1] || '';
    currentSub.value =
      !subParam && rawTab === 'logs' ? 'queries' : subParam.toLowerCase();

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
  currentSub.value = '';
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

  mql = window.matchMedia('(min-width: 1024px)');
  wideSidebar.value = mql.matches;
  mql.addEventListener('change', (e) => (wideSidebar.value = e.matches));

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
  if (mql) mql.removeEventListener('change', () => {});
  if (unsubConn) unsubConn();
  if (unsubAuth) unsubAuth();
});
</script>

<template>
  <div class="flex h-screen w-screen overflow-hidden bg-surface-base text-text-main font-sans antialiased select-none">
    <!-- 侧边导航：宽屏文本栏（w-56）／中屏图标栏（w-16） -->
    <nav
      class="hidden md:flex shrink-0 flex-col py-4 border-r border-surface-border bg-surface-base z-20"
      :class="wideSidebar ? 'w-56' : 'w-16'"
    >
      <!-- 品牌：朱色印章 + 宋体字标 -->
      <div
        class="flex items-center gap-2.5 px-4 mb-5 cursor-pointer"
        :class="wideSidebar ? '' : 'justify-center px-0'"
        @click="handleNavigate('overview')"
      >
        <span
          class="relative w-8 h-8 shrink-0 rounded-md bg-accent-seal text-white font-serif text-[16px] flex items-center justify-center"
        >
          谛
          <span
            class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-surface-base"
            :class="isConnected ? 'bg-status-success' : 'bg-status-error'"
            :title="isConnected ? '后台服务已连接' : '后台服务未连接'"
          />
        </span>
        <div v-if="wideSidebar" class="flex flex-col leading-none min-w-0">
          <span class="font-serif text-[15px] font-semibold text-text-main">谛听</span>
          <span class="label-quiet mt-1">DITING DNS</span>
        </div>
      </div>

      <!-- 导航项 -->
      <div class="flex flex-col gap-0.5 px-2" :class="wideSidebar ? '' : 'items-center px-0'">
        <NavItem
          v-for="item in navItems"
          :key="item.id"
          :id="item.id"
          :label="item.label"
          :icon="item.icon"
          :active="currentTab === item.id"
          :icon-only="!wideSidebar"
          @navigate="handleNavigate"
        />
      </div>
    </nav>

    <!-- 小屏底部导航栏 -->
    <nav class="md:hidden fixed bottom-0 left-0 right-0 h-14 z-30 bg-surface-card/95 backdrop-blur-md border-t border-surface-border flex items-center justify-around px-1">
      <NavItem
        v-for="item in navItems"
        :key="item.id"
        :id="item.id"
        :label="item.label"
        :icon="item.icon"
        :active="currentTab === item.id"
        icon-only
        @navigate="handleNavigate"
      />
    </nav>

    <!-- 主视口 -->
    <main class="flex-1 flex flex-col h-full overflow-hidden bg-surface-base">
      <!-- 顶栏 -->
      <header class="h-13 shrink-0 flex items-center justify-between gap-3 px-4 sm:px-6 py-2.5 border-b border-surface-border bg-surface-base">
        <div class="flex items-baseline gap-3 min-w-0">
          <span class="font-serif text-[15px] font-semibold text-text-main truncate">
            {{ currentNav?.label }}
          </span>
          <span class="text-[12px] text-text-muted truncate hidden sm:inline">
            {{ currentNav?.hint }}
          </span>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <!-- 环境标识 -->
          <span class="label-quiet hidden lg:inline font-mono">
            {{ webMode ? '局域网 Web 控制台' : `Windows v${appVersion}` }}
          </span>

          <!-- 用户态与登出 -->
          <div v-if="currentUser" class="flex items-center gap-2">
            <span class="text-[12px] text-text-sub hidden sm:inline">
              <span class="text-text-muted">管理员</span>
              <span class="font-mono ml-1.5">{{ currentUser }}</span>
            </span>
            <button
              v-if="webMode"
              type="button"
              @click="handleLogout"
              class="app-btn-secondary app-btn-compact"
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

      <!-- 视图容器（小屏预留底部导航安全间距） -->
      <div class="flex-1 overflow-y-auto px-4 sm:px-6 py-4 sm:py-5 pb-20 md:pb-5">
        <OverviewView
          v-if="currentTab === 'overview'"
          :sub="currentSub"
          @navigate="handleNavigate"
        />
        <NetworkView v-else-if="currentTab === 'network'" :sub="currentSub" />
        <AccelView v-else-if="currentTab === 'accel'" />
        <RulesView v-else-if="currentTab === 'rules'" :sub="currentSub" />
        <SystemView v-else-if="currentTab === 'system'" />
      </div>
    </main>

    <!-- 后台核心服务管理弹窗 -->
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
