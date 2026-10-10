<script setup lang="ts">
import { ref, watch } from 'vue';
import { ipc } from '../api/ipc';
import type { CoreServiceStatus } from '../api/types';
import M3Icon from './M3Icon.vue';
import AppModal from './AppModal.vue';

const props = defineProps<{
  open: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'connected'): void;
}>();

const coreServiceStatus = ref<CoreServiceStatus | null>(null);
const isStatusLoading = ref(false);
const serviceOperating = ref(false);
const serviceOpText = ref('');
const serviceOpError = ref('');
const isRetrying = ref(false);

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

async function retryConnect(): Promise<boolean> {
  if (isRetrying.value) return false;
  isRetrying.value = true;
  try {
    const healthy = await ipc.checkHealth();
    ipc.reconnectWS();
    if (healthy) {
      emit('connected');
      emit('close');
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
    if (!healthy) {
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
    if (!healthy) {
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

watch(
  () => props.open,
  (open) => {
    if (open) {
      serviceOpError.value = '';
      loadCoreServiceStatus();
    }
  }
);
</script>

<template>
  <AppModal
    :open="open"
    @close="emit('close')"
    type="alert"
  >
    <template #headline>
      <div
        class="flex items-center gap-2 font-bold"
        :class="
          isStatusLoading
            ? 'text-text-main'
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
      <div class="flex items-center justify-between p-3 rounded-md bg-surface-card-sub border border-surface-border">
        <div class="flex items-center gap-2">
          <span class="text-xs font-semibold text-text-sub">当前服务状态:</span>
          <span
            class="px-2 py-0.5 rounded-full text-[11px] font-bold"
            :class="[
              isStatusLoading
                ? 'bg-brand-container text-text-main'
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

      <div v-if="isStatusLoading" class="p-4 flex flex-col items-center justify-center gap-2 text-xs text-text-sub">
        <M3Icon name="sync" :size="20" class="animate-spin text-text-main" />
        <span>正在与系统服务管理器通讯以确认核心服务状态...</span>
      </div>

      <div v-else-if="!coreServiceStatus || !coreServiceStatus.installed" class="space-y-2 text-xs text-text-sub leading-relaxed">
        <p>检测到当前 Windows 系统尚未安装谛听核心特权服务组件。</p>
        <p>核心服务负责双栈物理网卡 DNS 安全接管与多协议上游转发。点击下方<b>“安装服务”</b>或<b>“安装并启动服务”</b>，客户端将自动向系统注册服务并按需申请管理员权限。</p>
        <div v-if="coreServiceStatus?.executablePath" class="text-[11px] font-mono text-text-muted truncate" :title="coreServiceStatus.executablePath">
          组件位置: {{ coreServiceStatus.executablePath }}
        </div>
      </div>

      <div v-else-if="!coreServiceStatus.running" class="space-y-2 text-xs text-text-sub leading-relaxed">
        <p>后台核心服务已向系统注册，但当前处于<b>停止状态</b>。</p>
        <p>点击下方<b>“启动服务”</b>即可直接恢复网络加速与防护，系统将在需要时按需申请系统权限。</p>
      </div>

      <div v-else class="space-y-2 text-xs text-text-sub leading-relaxed">
        <p>核心服务进程已在系统中运行，但客户端尚未成功建立通信。可能服务正在启动初始化中，或者本地端口被占用。</p>
        <p>您可以点击“重新连接”尝试握手，或点击“重启服务”刷新服务状态。</p>
      </div>

      <div
        v-if="serviceOperating"
        class="p-2.5 rounded-md bg-brand-container text-text-main border border-accent-seal/20 text-xs flex items-center gap-2"
      >
        <M3Icon name="refresh" :size="15" class="animate-spin" />
        <span>{{ serviceOpText }}</span>
      </div>

      <div
        v-if="serviceOpError"
        class="p-2.5 rounded-md bg-status-error-bg text-status-error border border-status-error/30 text-xs flex items-center gap-2"
      >
        <M3Icon name="error" :size="15" />
        <span>{{ serviceOpError }}</span>
      </div>
    </div>

    <template #actions>
      <button
        @click="emit('close')"
        :disabled="serviceOperating"
        class="app-btn-secondary"
      >
        稍后处理
      </button>

      <template v-if="!coreServiceStatus || !coreServiceStatus.installed">
        <button
          @click="handleInstallService"
          :disabled="serviceOperating || !coreServiceStatus?.canInstall"
          class="app-btn-secondary"
        >
          <M3Icon name="add" :size="16" />
          <span>仅安装服务</span>
        </button>
        <button
          @click="handleInstallAndStart"
          :disabled="serviceOperating || !coreServiceStatus?.canInstall"
          class="app-btn-primary"
        >
          <M3Icon name="bolt" :size="16" />
          <span>{{ serviceOperating ? '正在处理...' : '一键安装并启动服务' }}</span>
        </button>
      </template>

      <template v-else-if="!coreServiceStatus.running">
        <button
          @click="handleInstallService"
          :disabled="serviceOperating || !coreServiceStatus?.canInstall"
          class="app-btn-secondary"
        >
          <M3Icon name="build" :size="16" />
          <span>重新安装服务</span>
        </button>
        <button
          @click="handleStartService"
          :disabled="serviceOperating"
          class="app-btn-primary"
        >
          <M3Icon name="play_arrow" :size="16" />
          <span>{{ serviceOperating ? '正在启动...' : '启动服务' }}</span>
        </button>
      </template>

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
</template>
