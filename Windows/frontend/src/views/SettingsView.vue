<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import { themeManager, CLASSIC_SKY_BLUE, type ThemeMode } from '../theme/dynamic-color';
import type { PortCheckResult } from '../api/types';
import M3Icon from '../components/M3Icon.vue';

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
    restoreMessage.value = msg || '应急恢复指令已执行完成！';
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
  <div class="space-y-6 pb-12">
    <div>
      <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
        控制台配置与系统工具
      </h2>
      <p class="text-sm text-slate-500 dark:text-slate-400">
        特权服务 IPC 通信、Material Design 3 动态色彩体系与端口容灾诊断。
      </p>
    </div>

    <!-- 1. IPC 通信配置卡片 -->
    <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-6 shadow-sm backdrop-blur space-y-4">
      <h3 class="text-base font-bold text-slate-900 dark:text-slate-100 flex items-center gap-2">
        <M3Icon name="router" :size="20" class="text-slate-500" />
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
        <div v-if="connResult" class="text-xs font-medium flex items-center gap-2" :class="connResult.success ? 'text-emerald-600 dark:text-emerald-400' : 'text-rose-600 dark:text-rose-400'">
          <M3Icon :name="connResult.success ? 'check_circle' : 'error'" :size="16" />
          <span>{{ connResult.message }}</span>
        </div>
        <div v-else />

        <div class="flex items-center gap-3">
          <md-outlined-button @click="testConnection" :disabled="testingConnection">
            <M3Icon name="sync" slot="icon" :size="16" />
            测试连通性
          </md-outlined-button>
          <md-filled-button @click="handleSaveIPC">保存通信配置</md-filled-button>
        </div>
      </div>
    </div>

    <!-- 2. 外观与 M3 动态色彩体系 -->
    <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-6 shadow-sm backdrop-blur space-y-5">
      <h3 class="text-base font-bold text-slate-900 dark:text-slate-100 flex items-center gap-2">
        <M3Icon name="palette" :size="20" class="text-slate-500" />
        外观与 Material Design 3 动态色彩
      </h3>

      <!-- 明暗模式切换 -->
      <div class="space-y-2">
        <label class="text-xs font-semibold text-slate-500 block">主题色彩模式</label>
        <div class="flex flex-wrap gap-3">
          <button
            v-for="m in ([{ id: 'system', name: '跟随系统' }, { id: 'light', name: '浅色模式' }, { id: 'dark', name: '深色模式' }] as const)"
            :key="m.id"
            @click="handleModeChange(m.id)"
            class="px-4 py-2 rounded-xl text-xs font-bold transition-all duration-150 border"
            :class="[
              currentMode === m.id
                ? 'bg-primary text-on-primary border-primary shadow-sm'
                : 'bg-slate-100 dark:bg-slate-800/80 border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700',
            ]"
          >
            {{ m.name }}
          </button>
        </div>
      </div>

      <!-- 品牌基准主色锁定说明 -->
      <div class="pt-2 border-t border-slate-200/40 dark:border-slate-800/60">
        <div class="flex items-center justify-between p-3.5 rounded-xl border border-sky-100 dark:border-sky-950/60 bg-sky-50/50 dark:bg-sky-950/20">
          <div class="flex items-center gap-3">
            <span class="w-5 h-5 rounded-lg bg-[#0288D1] shadow-sm flex items-center justify-center shrink-0 border border-white/20">
              <span class="w-1.5 h-1.5 rounded-full bg-white"></span>
            </span>
            <div>
              <div class="text-xs font-bold text-slate-800 dark:text-slate-200 flex items-center gap-2">
                <span>Material Design 经典天蓝色</span>
                <span class="font-mono text-[11px] text-sky-700 dark:text-sky-300 bg-sky-100 dark:bg-sky-900/60 px-1.5 py-0.5 rounded">#0288D1</span>
              </div>
              <div class="text-[11px] text-slate-500 dark:text-slate-400">
                系统全域统一主色调，基于 M3 规范实时生成动态光暗语义色盘与容器层次
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. 系统诊断与容灾工具 -->
    <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-6 shadow-sm backdrop-blur space-y-4">
      <h3 class="text-base font-bold text-slate-900 dark:text-slate-100 flex items-center gap-2">
        <M3Icon name="shield" :size="20" class="text-slate-500" />
        系统诊断与容灾自愈工具
      </h3>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <!-- Windows 开机自启 -->
        <div class="p-4 rounded-xl border border-slate-200/60 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-950/30 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-slate-800 dark:text-slate-200">开机自动启动</span>
            <md-switch
              :selected="autostart"
              :disabled="togglingAutostart"
              @change="handleToggleAutostart"
            />
          </div>
          <p class="text-xs text-slate-500 dark:text-slate-400">
            开机登录系统时自动启动客户端，保障 DNS 监控与状态持久化无缝运作。
          </p>
        </div>

        <!-- 端口诊断 -->
        <div class="p-4 rounded-xl border border-slate-200/60 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-950/30 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-slate-800 dark:text-slate-200">53 端口冲突检测</span>
            <md-outlined-button @click="handleDiagnosePort" :disabled="diagnosingPort">
              <md-circular-progress v-if="diagnosingPort" indeterminate slot="icon" class="w-4 h-4" />
              <M3Icon v-else name="search" slot="icon" :size="16" />
              诊断端口
            </md-outlined-button>
          </div>
          <p class="text-xs text-slate-500 dark:text-slate-400">
            检测 127.0.0.1:53 是否被 SharedAccess (ICS) 或其他第三方 DNS 软件占用。
          </p>
          <div v-if="portResult" class="p-3 rounded-lg bg-slate-100 dark:bg-slate-800 text-xs space-y-1">
            <div class="font-semibold" :class="portResult.available ? 'text-emerald-600 dark:text-emerald-400' : 'text-amber-500'">
              {{ portResult.available ? '53 端口可用' : '检测到端口占用或冲突' }}
            </div>
            <p class="text-slate-600 dark:text-slate-300 whitespace-pre-line">{{ portResult.diagnostic }}</p>
          </div>
        </div>

        <!-- 应急自愈脚本 -->
        <div class="p-4 rounded-xl border border-slate-200/60 dark:border-slate-800/60 bg-slate-50/50 dark:bg-slate-950/30 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-slate-800 dark:text-slate-200">离线 DNS 应急恢复</span>
            <md-filled-button @click="handleEmergencyRestore" :disabled="restoring">
              <md-circular-progress v-if="restoring" indeterminate slot="icon" class="w-4 h-4" />
              <M3Icon v-else name="refresh" slot="icon" :size="16" />
              执行自愈
            </md-filled-button>
          </div>
          <p class="text-xs text-slate-500 dark:text-slate-400">
            当极端异常导致系统网卡未还原时，一键从持久化快照完全还原原生 DNS。
          </p>
          <div v-if="restoreMessage" class="p-3 rounded-lg bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 text-xs font-semibold">
            {{ restoreMessage }}
          </div>
        </div>
      </div>
    </div>

    <!-- 离线恢复确认对话框 (M3 Alert Dialog) -->
    <md-dialog :open="showRestoreDialog" @close="showRestoreDialog = false" type="alert">
      <div slot="headline" class="flex items-center gap-2 text-amber-600 dark:text-amber-400">
        <M3Icon name="warning" :size="24" />
        <span>确认执行系统 DNS 应急自愈？</span>
      </div>
      <form slot="content" id="restore-form" method="dialog" class="space-y-2 text-xs text-slate-600 dark:text-slate-400">
        <p>此操作将扫描 <code>%ProgramData%\DITING\dns_state.json</code> 持久化状态快照，将所有已接管物理网卡强制还原回 DHCP 或原静态 DNS 设置，并执行系统 DNS 缓存刷新。</p>
        <p>适用于后台特权服务非正常退出、或系统网卡 DNS 指向残留需要一键脱困的场景。</p>
      </form>
      <div slot="actions">
        <md-text-button form="restore-form" value="cancel" @click="showRestoreDialog = false">取消</md-text-button>
        <md-filled-button form="restore-form" value="confirm" @click="doEmergencyRestore">确认自愈恢复</md-filled-button>
      </div>
    </md-dialog>
  </div>
</template>
