<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import type { CoreServiceStatus } from '../api/types';
import M3Icon from './M3Icon.vue';
import StatusBadge from './StatusBadge.vue';

const serviceStatus = ref<CoreServiceStatus | null>(null);
const loading = ref(false);
const operating = ref(false);
const opMessage = ref('');
const opError = ref('');

async function fetchStatus() {
  loading.value = true;
  opError.value = '';
  try {
    serviceStatus.value = await ipc.getCoreServiceStatus();
  } catch (err: any) {
    opError.value = err.message || '获取服务状态失败';
  } finally {
    loading.value = false;
  }
}

async function handleAction(action: 'start' | 'stop' | 'restart' | 'install' | 'install_and_start' | 'uninstall') {
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
    opMessage.value = msg || '操作成功完成';
    // 操作后重新拉取最新状态
    await fetchStatus();
    // 尝试健康检查更新前端连接
    await ipc.checkHealth();
  } catch (err: any) {
    opError.value = err.message || '操作失败';
  } finally {
    operating.value = false;
  }
}

onMounted(() => {
  fetchStatus();
});
</script>

<template>
  <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs space-y-4 transition-colors">
    <div class="flex items-center justify-between">
      <h3 class="text-base font-bold text-text-main flex items-center gap-2">
        <M3Icon name="router" :size="20" class="text-brand-primary" />
        后台核心服务管理
      </h3>
      <button
        type="button"
        @click="fetchStatus"
        :disabled="loading || operating"
        class="app-btn-secondary app-btn-compact"
        title="刷新核心服务状态"
      >
        <M3Icon name="refresh" :size="14" :class="loading ? 'animate-spin' : ''" />
        <span>刷新状态</span>
      </button>
    </div>

    <!-- 状态概览卡片区 -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- 1. 服务运行状态 -->
      <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-2">
        <span class="text-xs font-semibold text-text-sub">系统服务状态</span>
        <div class="flex items-center gap-2 pt-1">
          <StatusBadge
            v-if="serviceStatus?.installed && serviceStatus?.running"
            status="active"
            text="运行中"
            pulse
          />
          <StatusBadge
            v-else-if="serviceStatus?.installed && !serviceStatus?.running"
            status="warning"
            text="已停止"
          />
          <StatusBadge
            v-else-if="serviceStatus && !serviceStatus.installed"
            status="error"
            text="未安装"
          />
          <StatusBadge
            v-else
            status="inactive"
            text="检测中..."
          />
          <span class="text-xs text-text-muted">
            ({{ serviceStatus?.stateText || '未知' }})
          </span>
        </div>
        <p class="text-[11px] text-text-sub leading-tight">
          {{ serviceStatus?.message || '负责双栈网卡接管与 DNS 转发' }}
        </p>
      </div>

      <!-- 2. 可执行程序路径 -->
      <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-2">
        <span class="text-xs font-semibold text-text-sub">组件文件位置</span>
        <div class="font-mono text-[11px] text-text-main break-all line-clamp-2 pt-1" :title="serviceStatus?.executablePath">
          {{ serviceStatus?.executablePath || '未检测到可执行程序' }}
        </div>
        <p class="text-[11px]" :class="serviceStatus?.canInstall ? 'text-status-success' : 'text-status-warning'">
          {{ serviceStatus?.canInstall ? '✔ 服务核心文件就绪' : '⚠ 未检测到 diting-service.exe' }}
        </p>
      </div>

      <!-- 3. 管理权限模式 -->
      <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-2">
        <span class="text-xs font-semibold text-text-sub">系统权限级别</span>
        <div class="flex items-center gap-1.5 pt-1">
          <M3Icon name="shield" :size="16" :class="serviceStatus?.isElevated ? 'text-status-success' : 'text-brand-primary'" />
          <span class="text-xs font-bold text-text-main">
            {{ serviceStatus?.isElevated ? '管理员特权模式' : '标准用户 (按需授权)' }}
          </span>
        </div>
        <p class="text-[11px] text-text-sub leading-tight">
          {{ serviceStatus?.isElevated ? '已具备管理员权限，操作无需弹窗' : '点击操作时将自动唤起 Windows 提权弹窗' }}
        </p>
      </div>
    </div>

    <!-- 反馈通知横幅 -->
    <div
      v-if="opMessage"
      class="p-3 rounded-lg bg-status-success-bg text-status-success border border-status-success/30 text-xs font-semibold flex items-center gap-2"
    >
      <M3Icon name="check_circle" :size="16" />
      <span>{{ opMessage }}</span>
    </div>

    <div
      v-if="opError"
      class="p-3 rounded-lg bg-status-error-bg text-status-error border border-status-error/30 text-xs font-semibold flex items-center gap-2"
    >
      <M3Icon name="error" :size="16" />
      <span>{{ opError }}</span>
    </div>

    <!-- 操作工具栏 -->
    <div class="flex flex-wrap items-center justify-between gap-3 pt-1">
      <div v-if="ipc.isWebMode()" class="w-full flex items-center gap-2 text-xs text-text-sub bg-surface-card-sub p-3 rounded-xl border border-surface-border">
        <M3Icon name="info" :size="16" class="text-brand-primary shrink-0" />
        <span>当前为局域网 Web 远程管理控制台，后台服务正在宿主机守护运行中。Windows 系统服务注册与提权安装仅限在宿主机桌面端操作。</span>
      </div>
      <template v-else>
        <div class="text-xs text-text-sub flex items-center gap-1.5">
          <M3Icon name="info" :size="15" class="text-text-muted" />
          <span>支持一键向 Windows 注册服务并开机托管，操作将在需要时请求管理员权限。</span>
        </div>

        <div class="flex items-center gap-2">
          <!-- 未安装状态：提供安装服务 -->
          <template v-if="serviceStatus && !serviceStatus.installed">
            <button
              type="button"
              @click="handleAction('install')"
              :disabled="operating || !serviceStatus.canInstall"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon name="add" :size="14" />
              <span>仅注册服务</span>
            </button>
            <button
              type="button"
              @click="handleAction('install_and_start')"
              :disabled="operating || !serviceStatus.canInstall"
              class="app-btn-primary app-btn-compact"
            >
              <M3Icon name="bolt" :size="14" />
              <span>{{ operating ? '正在处理...' : '一键安装并启动' }}</span>
            </button>
          </template>

          <!-- 已安装但已停止：提供启动与卸载 -->
          <template v-else-if="serviceStatus?.installed && !serviceStatus?.running">
            <button
              type="button"
              @click="handleAction('uninstall')"
              :disabled="operating"
              class="app-btn-danger app-btn-compact"
            >
              <M3Icon name="delete" :size="14" />
              <span>卸载服务</span>
            </button>
            <button
              type="button"
              @click="handleAction('start')"
              :disabled="operating"
              class="app-btn-primary app-btn-compact"
            >
              <M3Icon name="play_arrow" :size="14" />
              <span>{{ operating ? '正在启动...' : '启动服务' }}</span>
            </button>
          </template>

          <!-- 已安装且运行中：提供重启与停止 -->
          <template v-else-if="serviceStatus?.installed && serviceStatus?.running">
            <button
              type="button"
              @click="handleAction('stop')"
              :disabled="operating"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon name="pause" :size="14" />
              <span>停止服务</span>
            </button>
            <button
              type="button"
              @click="handleAction('restart')"
              :disabled="operating"
              class="app-btn-primary app-btn-compact"
            >
              <M3Icon name="refresh" :size="14" :class="operating ? 'animate-spin' : ''" />
              <span>{{ operating ? '正在重启...' : '重启服务' }}</span>
            </button>
          </template>
        </div>
      </template>
    </div>
  </div>
</template>
