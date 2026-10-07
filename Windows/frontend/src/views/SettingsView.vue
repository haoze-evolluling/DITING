<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import { themeManager, CLASSIC_SKY_BLUE, type ThemeMode } from '../theme/dynamic-color';
import type { PortCheckResult } from '../api/types';
import M3Icon from '../components/M3Icon.vue';
import AppModal from '../components/AppModal.vue';

const host = ref('127.0.0.1');
const port = ref('15353');
const token = ref('');
const testingConnection = ref(false);
const connResult = ref<{ success: boolean; message: string } | null>(null);

// 主题状态
const currentMode = ref<ThemeMode>(themeManager.getThemeMode());

// 端口诊断状态
const diagnosingPort = ref(false);
const portResult = ref<PortCheckResult | null>(null);

// 应急恢复状态
const restoring = ref(false);
const restoreMessage = ref('');
const showRestoreDialog = ref(false);

// 开机自启状态
const autostart = ref(false);
const togglingAutostart = ref(false);

async function checkAutostart() {
  try {
    autostart.value = await ipc.isAutoStartEnabled();
  } catch {}
}

async function handleToggleAutostart(e: Event) {
  const target = e.target as any;
  const enable = Boolean(target.selected ?? target.checked);
  togglingAutostart.value = true;
  try {
    autostart.value = await ipc.setAutoStart(enable);
  } catch (err: any) {
    alert(`设置开机自启失败: ${err.message}`);
    if ('selected' in target) {
      target.selected = !enable;
    } else {
      target.checked = !enable;
    }
  } finally {
    togglingAutostart.value = false;
  }
}

function loadSettings() {
  const cfg = ipc.getConfig();
  host.value = cfg.host;
  port.value = cfg.port;
  token.value = cfg.token;
  currentMode.value = themeManager.getThemeMode();
  checkAutostart();
}

async function testConnection() {
  testingConnection.value = true;
  connResult.value = null;
  ipc.saveConfig(host.value, port.value, token.value);
  try {
    const ok = await ipc.checkHealth();
    if (ok) {
      connResult.value = { success: true, message: '成功连通特权服务 (127.0.0.1:15353)' };
    } else {
      connResult.value = { success: false, message: '服务无响应，请确认 diting-service 正在运行' };
    }
  } catch (err: any) {
    connResult.value = { success: false, message: err.message || '连接失败' };
  } finally {
    testingConnection.value = false;
  }
}

function handleSaveIPC() {
  ipc.saveConfig(host.value, port.value, token.value);
  testConnection();
}

function handleModeChange(mode: ThemeMode) {
  currentMode.value = mode;
  themeManager.setThemeMode(mode);
}

async function handleDiagnosePort() {
  diagnosingPort.value = true;
  portResult.value = null;
  try {
    const res = await ipc.checkPortConflicts();
    portResult.value = res;
  } catch (err: any) {
    alert(`诊断失败: ${err.message}`);
  } finally {
    diagnosingPort.value = false;
  }
}

function handleEmergencyRestore() {
  showRestoreDialog.value = true;
}

async function doEmergencyRestore() {
  showRestoreDialog.value = false;
  restoring.value = true;
  restoreMessage.value = '';
  try {
    const msg = await ipc.runNativeEmergencyRestore();
    restoreMessage.value = msg || '应急恢复指令已执行完成。';
  } catch (err: any) {
    restoreMessage.value = `恢复失败: ${err.message}`;
  } finally {
    restoring.value = false;
  }
}

onMounted(() => {
  loadSettings();
});
</script>

<template>
  <div class="space-y-6 pb-12 select-none">
    <div>
      <h2 class="text-2xl font-bold tracking-tight text-text-main">
        控制台配置与系统工具
      </h2>
      <p class="text-sm text-text-sub">
        特权服务 IPC 通信、现代高质感双色调色彩体系与端口容灾诊断。
      </p>
    </div>

    <!-- 1. IPC 通信配置卡片 -->
    <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs space-y-4 transition-colors">
      <h3 class="text-base font-bold text-text-main flex items-center gap-2">
        <M3Icon name="router" :size="20" class="text-brand-primary" />
        核心特权服务 IPC 通信
      </h3>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div>
          <md-outlined-text-field
            label="服务监听主机"
            :value="host"
            @input="host = ($event.target as any).value"
            class="w-full"
          ></md-outlined-text-field>
        </div>
        <div>
          <md-outlined-text-field
            label="IPC 端口"
            :value="port"
            @input="port = ($event.target as any).value"
            class="w-full font-mono"
          ></md-outlined-text-field>
        </div>
        <div>
          <md-outlined-text-field
            label="Token 鉴权密钥 (可选)"
            :value="token"
            @input="token = ($event.target as any).value"
            type="password"
            placeholder="留空即免密通信"
            class="w-full"
          ></md-outlined-text-field>
        </div>
      </div>

      <div class="flex items-center justify-between pt-2">
        <div v-if="connResult" class="text-xs font-medium flex items-center gap-2" :class="connResult.success ? 'text-status-success' : 'text-status-error'">
          <M3Icon :name="connResult.success ? 'check_circle' : 'error'" :size="16" />
          <span>{{ connResult.message }}</span>
        </div>
        <div v-else />

        <div class="flex items-center gap-3">
          <button
            type="button"
            @click="testConnection"
            :disabled="testingConnection"
            class="app-btn-secondary"
          >
            <M3Icon name="sync" :size="16" :class="testingConnection ? 'animate-spin' : ''" />
            <span>测试连通性</span>
          </button>
          <button
            type="button"
            @click="handleSaveIPC"
            class="app-btn-primary"
          >
            <M3Icon name="check" :size="16" />
            <span>保存通信配置</span>
          </button>
        </div>
      </div>
    </div>

    <!-- 2. 外观与现代高质感色彩体系 -->
    <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs space-y-5 transition-colors">
      <h3 class="text-base font-bold text-text-main flex items-center gap-2">
        <M3Icon name="palette" :size="20" class="text-brand-primary" />
        外观与现代色彩系统
      </h3>

      <!-- 明暗模式切换 -->
      <div class="space-y-2">
        <label class="text-xs font-semibold text-text-sub block">主题色彩模式</label>
        <div class="flex flex-wrap gap-3">
          <button
            v-for="m in ([{ id: 'system', name: '跟随系统' }, { id: 'light', name: '浅色模式' }, { id: 'dark', name: '深色模式' }] as const)"
            :key="m.id"
            @click="handleModeChange(m.id)"
            class="app-btn-base transition-all duration-150"
            :class="[
              currentMode === m.id
                ? 'bg-brand-primary text-white dark:text-sky-950 border-transparent shadow-xs'
                : 'bg-surface-card-sub border border-surface-border text-text-sub hover:bg-surface-hover',
            ]"
          >
            {{ m.name }}
          </button>
        </div>
      </div>

      <!-- 品牌基准主色锁定说明 -->
      <div class="pt-2 border-t border-surface-border">
        <div class="flex items-center justify-between p-3.5 rounded-xl border border-brand-primary/20 bg-brand-container/20">
          <div class="flex items-center gap-3">
            <span class="w-5 h-5 rounded-lg bg-[#0284c7] shadow-xs flex items-center justify-center shrink-0 border border-white/20">
              <span class="w-1.5 h-1.5 rounded-full bg-white"></span>
            </span>
            <div>
              <div class="text-xs font-bold text-text-main flex items-center gap-2">
                <span>经典天穹科技蓝 (Logo 标识色)</span>
                <span class="font-mono text-[11px] text-brand-primary bg-surface-card px-1.5 py-0.5 rounded border border-surface-border">#0284C7</span>
              </div>
              <div class="text-[11px] text-text-sub">
                系统全域统一主色调，规范浅色清爽纯净质感与深色暗夜深邃层次
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. 系统诊断与容灾工具 -->
    <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs space-y-4 transition-colors">
      <h3 class="text-base font-bold text-text-main flex items-center gap-2">
        <M3Icon name="shield" :size="20" class="text-brand-primary" />
        系统诊断与容灾自愈工具
      </h3>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <!-- Windows 开机自启 -->
        <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-text-main">开机自动启动</span>
            <md-switch
              :selected="autostart"
              :disabled="togglingAutostart"
              @change="handleToggleAutostart"
            />
          </div>
          <p class="text-xs text-text-sub">
            开机登录系统时自动启动客户端，保障 DNS 监控与状态持久化无缝运作。
          </p>
        </div>

        <!-- 端口诊断 -->
        <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-text-main">53 端口冲突检测</span>
            <button
              type="button"
              @click="handleDiagnosePort"
              :disabled="diagnosingPort"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon v-if="diagnosingPort" name="refresh" :size="14" class="animate-spin" />
              <M3Icon v-else name="search" :size="14" />
              <span>诊断端口</span>
            </button>
          </div>
          <p class="text-xs text-text-sub">
            检测 127.0.0.1:53 是否被 SharedAccess (ICS) 或其他第三方 DNS 软件占用。
          </p>
          <div v-if="portResult" class="p-3 rounded-lg bg-surface-card border border-surface-border text-xs space-y-1">
            <div class="font-semibold" :class="portResult.available ? 'text-status-success' : 'text-status-warning'">
              {{ portResult.available ? '53 端口可用' : '检测到端口占用或冲突' }}
            </div>
            <p class="text-text-sub whitespace-pre-line">{{ portResult.diagnostic }}</p>
          </div>
        </div>

        <!-- 应急自愈脚本 -->
        <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-text-main">离线 DNS 应急恢复</span>
            <button
              type="button"
              @click="handleEmergencyRestore"
              :disabled="restoring"
              class="app-btn-primary app-btn-compact"
            >
              <M3Icon v-if="restoring" name="refresh" :size="14" class="animate-spin" />
              <M3Icon v-else name="refresh" :size="14" />
              <span>执行自愈</span>
            </button>
          </div>
          <p class="text-xs text-text-sub">
            当极端异常导致系统网卡未还原时，一键从持久化快照完全还原原生 DNS。
          </p>
          <div v-if="restoreMessage" class="p-3 rounded-lg bg-status-success-bg text-status-success border border-status-success/30 text-xs font-semibold">
            {{ restoreMessage }}
          </div>
        </div>
      </div>
    </div>

    <!-- 离线恢复确认对话框 (使用 AppModal 居中架构) -->
    <AppModal
      :open="showRestoreDialog"
      @close="showRestoreDialog = false"
      type="alert"
    >
      <template #headline>
        <div class="flex items-center gap-2 text-status-warning font-bold">
          <M3Icon name="warning" :size="24" />
          <span>确认执行系统 DNS 应急自愈？</span>
        </div>
      </template>

      <div class="space-y-2 text-xs text-text-sub leading-relaxed">
        <p>此操作将扫描 <code>%ProgramData%\DITING\dns_state.json</code> 持久化状态快照，将所有已接管物理网卡强制还原回 DHCP 或原静态 DNS 设置，并执行系统 DNS 缓存刷新。</p>
        <p>适用于后台特权服务非正常退出、或系统网卡 DNS 指向残留需要一键脱困的场景。</p>
      </div>

      <template #actions>
        <button
          type="button"
          @click="showRestoreDialog = false"
          class="app-btn-secondary"
        >
          取消
        </button>
        <button
          type="button"
          @click="doEmergencyRestore"
          class="app-btn-warning"
        >
          确认自愈恢复
        </button>
      </template>
    </AppModal>
  </div>
</template>
