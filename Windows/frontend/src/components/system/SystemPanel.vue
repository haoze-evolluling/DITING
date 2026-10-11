<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../../api/ipc';
import { themeManager, type ThemeMode } from '../../theme/theme';
import type { PortCheckResult } from '../../api/types';
import M3Icon from '../M3Icon.vue';
import AppModal from '../AppModal.vue';
import ToastBanner from '../ToastBanner.vue';
import CoreServiceCard from '../CoreServiceCard.vue';
import LanWebCard from '../LanWebCard.vue';
import { revertSwitch, extractSwitchValue } from '../../utils/switch';
import { isWebMode } from '../../utils/env';
import { useToast } from '../../composables/useToast';

const webMode = isWebMode();
const { toast, show: showToast, dismiss } = useToast();
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
  const enable = extractSwitchValue(e);
  togglingAutostart.value = true;
  try {
    autostart.value = await ipc.setAutoStart(enable);
    showToast(`开机自启已${enable ? '开启' : '关闭'}`);
  } catch (err: any) {
    showToast(`设置开机自启失败: ${err.message}`, true);
    revertSwitch(e, !enable);
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
      connResult.value = { success: true, message: '成功连接后台核心服务' };
    } else {
      connResult.value = { success: false, message: '无法连接到后台服务，请确认核心服务已启动' };
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

const autofixingPort = ref(false);

async function handleDiagnosePort() {
  diagnosingPort.value = true;
  portResult.value = null;
  try {
    const res = await ipc.checkPortConflicts();
    portResult.value = res;
    if (res.available) {
      showToast('DNS 端口正常可用');
    } else {
      showToast('检测到 DNS 端口被占用或冲突', true);
    }
  } catch (err: any) {
    showToast(`诊断失败: ${err.message}`, true);
  } finally {
    diagnosingPort.value = false;
  }
}

async function handleAutofixInSettings() {
  autofixingPort.value = true;
  try {
    const res = await ipc.autofixPortConflicts(false);
    portResult.value = res;
    if (res.available) {
      showToast('已成功修复 DNS 端口冲突');
    } else {
      showToast('自动修复完成，但仍有冲突', true);
    }
  } catch (err: any) {
    showToast(`自动修复失败: ${err.message}`, true);
  } finally {
    autofixingPort.value = false;
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
    restoreMessage.value = msg || '网络设置已成功恢复。';
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
  <div class="space-y-5 select-none">
    <!-- 全局消息提示横幅 -->
    <ToastBanner
      v-if="toast"
      :message="toast.message"
      :type="toast.isError ? 'error' : 'success'"
      dismissible
      @dismiss="dismiss"
    />

    <!-- 1. IPC 通信配置卡片 -->
    <div class="app-panel p-5 space-y-4">
      <h3 class="section-title">后台服务连接</h3>
      <p class="text-[12px] text-text-muted -mt-2">配置客户端连接核心服务的地址与授权信息。</p>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div>
          <md-outlined-text-field
            label="服务地址 (IP 或主机名)"
            :value="host"
            @input="host = ($event.target as any).value"
            class="w-full"
          ></md-outlined-text-field>
        </div>
        <div>
          <md-outlined-text-field
            label="通信端口"
            :value="port"
            @input="port = ($event.target as any).value"
            class="w-full font-mono"
          ></md-outlined-text-field>
        </div>
        <div>
          <md-outlined-text-field
            label="访问密码 / 授权密钥 (可选)"
            :value="token"
            @input="token = ($event.target as any).value"
            type="password"
            placeholder="留空表示无需密码"
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
            <span>测试连接</span>
          </button>
          <button
            type="button"
            @click="handleSaveIPC"
            class="app-btn-primary"
          >
            <M3Icon name="check" :size="16" />
            <span>保存连接设置</span>
          </button>
        </div>
      </div>
    </div>

    <!-- 2. 外观与主题（墨朱体系） -->
    <div class="app-panel p-5 space-y-4">
      <h3 class="section-title">外观与主题</h3>

      <!-- 明暗模式切换 -->
      <div class="space-y-2">
        <label class="text-[12px] font-semibold text-text-sub block">界面色彩模式</label>
        <div class="flex flex-wrap gap-2.5">
          <button
            v-for="m in ([{ id: 'system', name: '跟随系统' }, { id: 'light', name: '浅色宣纸' }, { id: 'dark', name: '深色墨夜' }] as const)"
            :key="m.id"
            @click="handleModeChange(m.id)"
            class="app-btn-base"
            :class="[
              currentMode === m.id
                ? 'bg-brand-primary text-surface-card border border-brand-primary dark:text-[#1a1a1c]'
                : 'bg-surface-card-sub border border-surface-border text-text-sub hover:bg-surface-hover',
            ]"
          >
            {{ m.name }}
          </button>
        </div>
      </div>

      <!-- 墨·朱 视觉规范说明 -->
      <div class="pt-3 border-t border-surface-border flex items-center gap-3">
        <div class="flex items-center -space-x-1 shrink-0">
          <span class="w-5 h-5 rounded-md bg-[#1A1A1C] border border-surface-border z-10" title="墨 #1A1A1C"></span>
          <span class="w-5 h-5 rounded-md bg-[#8A8B8E] border border-surface-border" title="灰 #8A8B8E"></span>
          <span class="w-5 h-5 rounded-md bg-[#F1EFE9] border border-surface-border" title="宣纸 #F1EFE9"></span>
          <span class="w-5 h-5 rounded-md bg-[#9E2B25] border border-surface-border" title="朱砂 #9E2B25"></span>
        </div>
        <div>
          <div class="text-[12px] font-semibold text-text-main">
            墨 · 朱 视觉体系
          </div>
          <div class="text-[11px] text-text-muted">
            以黑灰白墨色为主调，朱砂红仅用于强调与危险操作，深浅两套对等适配。
          </div>
        </div>
      </div>
    </div>

    <!-- 3. 后台核心服务管理 -->
    <CoreServiceCard />

    <!-- 4. 局域网 Web 远程管理控制台 -->
    <LanWebCard />

    <!-- 5. 系统诊断与容灾工具 -->
    <div class="app-panel p-5 space-y-4">
      <h3 class="section-title">网络诊断与应急修复</h3>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <!-- Windows 开机自启 -->
        <div class="p-4 rounded-md border border-surface-border-sub bg-surface-card-sub space-y-2.5">
          <div class="flex items-center justify-between gap-2">
            <span class="text-[13px] font-semibold text-text-main">开机自动启动</span>
            <span v-if="webMode" class="text-[11px] text-text-muted bg-surface-card px-2 py-0.5 rounded border border-surface-border">仅限宿主机桌面</span>
            <md-switch
              v-else
              :selected="autostart"
              :disabled="togglingAutostart"
              @change="handleToggleAutostart"
            />
          </div>
          <p class="text-[12px] text-text-sub leading-relaxed">
            开机登录 Windows 时自动启动客户端，确保持续提供网络加速与安全防护。
          </p>
        </div>

        <!-- 端口诊断 -->
        <div class="p-4 rounded-md border border-surface-border-sub bg-surface-card-sub space-y-2.5">
          <div class="flex items-center justify-between gap-2">
            <span class="text-[13px] font-semibold text-text-main">DNS 端口冲突检测</span>
            <button
              type="button"
              @click="handleDiagnosePort"
              :disabled="diagnosingPort"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon v-if="diagnosingPort" name="refresh" :size="14" class="animate-spin" />
              <M3Icon v-else name="search" :size="14" />
              <span>开始检测</span>
            </button>
          </div>
          <p class="text-[12px] text-text-sub leading-relaxed">
            检测标准 DNS 端口 (53) 是否被系统网络共享 (ICS) 或其他网络软件占用。
          </p>
          <div v-if="portResult" class="p-3 rounded-md bg-surface-card border border-surface-border text-[12px] space-y-2">
            <div class="font-semibold" :class="portResult.available ? 'text-status-success' : 'text-status-warning'">
              {{ portResult.available ? 'DNS 端口正常可用' : '检测到端口被占用或冲突' }}
            </div>
            <p class="text-text-sub whitespace-pre-line">{{ portResult.diagnostic }}</p>
            <div v-if="!portResult.available && (portResult.canAutofix || portResult.hasICS)" class="pt-1">
              <button
                type="button"
                @click="handleAutofixInSettings"
                :disabled="autofixingPort"
                class="app-btn-primary app-btn-compact"
              >
                <M3Icon :name="autofixingPort ? 'refresh' : 'bolt'" :size="12" :class="autofixingPort ? 'animate-spin' : ''" />
                <span>{{ autofixingPort ? '正在修复...' : '一键自动修复 ICS 冲突' }}</span>
              </button>
            </div>
          </div>
        </div>

        <!-- 应急自愈脚本 -->
        <div class="p-4 rounded-md border border-surface-border-sub bg-surface-card-sub space-y-2.5">
          <div class="flex items-center justify-between gap-2">
            <span class="text-[13px] font-semibold text-text-main">一键恢复网络设置</span>
            <span v-if="webMode" class="text-[11px] text-text-muted bg-surface-card px-2 py-0.5 rounded border border-surface-border">仅限宿主机桌面</span>
            <button
              v-else
              type="button"
              @click="handleEmergencyRestore"
              :disabled="restoring"
              class="app-btn-primary app-btn-compact"
            >
              <M3Icon v-if="restoring" name="refresh" :size="14" class="animate-spin" />
              <M3Icon v-else name="refresh" :size="14" />
              <span>一键修复</span>
            </button>
          </div>
          <p class="text-[12px] text-text-sub leading-relaxed">
            当异常关闭导致电脑无法上网时，一键自动修复并将网络 DNS 还原为系统默认设置。
          </p>
          <div v-if="restoreMessage" class="p-3 rounded-md bg-status-success-bg text-status-success border border-status-success/30 text-[12px] font-semibold">
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
          <span>确定一键恢复网络设置？</span>
        </div>
      </template>

      <div class="space-y-2 text-xs text-text-sub leading-relaxed">
        <p>此操作将安全恢复所有网络连接的原有 DNS 设置（恢复为自动获取或原有设置），并刷新网络缓存。</p>
        <p>适用于因软件异常退出导致电脑无法打开网页、需要紧急恢复上网的场景。</p>
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
          立即修复网络
        </button>
      </template>
    </AppModal>
  </div>
</template>
