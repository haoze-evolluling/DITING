<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import { themeManager, PRESET_SEED_COLORS, type ThemeMode } from '../theme/dynamic-color';
import type { PortCheckResult } from '../api/types';
import M3Icon from '../components/M3Icon.vue';

const host = ref('127.0.0.1');
const port = ref('15353');
const token = ref('');
const testingConnection = ref(false);
const connResult = ref<{ success: boolean; message: string } | null>(null);

// 主题状态
const currentSeed = ref(themeManager.getSeedColor());
const currentMode = ref<ThemeMode>(themeManager.getThemeMode());
const useAccent = ref(themeManager.isUsingSystemAccent());

// 端口诊断状态
const diagnosingPort = ref(false);
const portResult = ref<PortCheckResult | null>(null);

// 应急恢复状态
const restoring = ref(false);
const restoreMessage = ref('');

function loadSettings() {
  const cfg = ipc.getConfig();
  host.value = cfg.host;
  port.value = cfg.port;
  token.value = cfg.token;
  currentSeed.value = themeManager.getSeedColor();
  currentMode.value = themeManager.getThemeMode();
  useAccent.value = themeManager.isUsingSystemAccent();
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

function handleSelectSeed(hex: string) {
  currentSeed.value = hex;
  useAccent.value = false;
  themeManager.setUseSystemAccent(false);
  themeManager.setSeedColor(hex);
}

function handleCustomSeedChange(e: Event) {
  const target = e.target as HTMLInputElement;
  handleSelectSeed(target.value);
}

function handleModeChange(mode: ThemeMode) {
  currentMode.value = mode;
  themeManager.setThemeMode(mode);
}

async function handleToggleAccent(e: Event) {
  const target = e.target as HTMLInputElement;
  const enable = target.checked;
  useAccent.value = enable;
  if (enable) {
    const accent = await ipc.getNativeSystemAccentColor();
    currentSeed.value = accent;
    themeManager.setUseSystemAccent(true, accent);
  } else {
    themeManager.setUseSystemAccent(false);
  }
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

async function handleEmergencyRestore() {
  if (!confirm('确认执行离线系统 DNS 应急自愈恢复？这会将所有物理网卡恢复至初始快照。')) {
    return;
  }
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
          <label class="text-xs font-semibold text-slate-500 block mb-1">服务监听主机</label>
          <input
            v-model="host"
            type="text"
            class="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 text-slate-900 dark:text-slate-100"
          />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-500 block mb-1">IPC 端口</label>
          <input
            v-model="port"
            type="text"
            class="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-primary/40 text-slate-900 dark:text-slate-100"
          />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-500 block mb-1">Token 鉴权密钥 (可选)</label>
          <input
            v-model="token"
            type="password"
            placeholder="留空即免密通信"
            class="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 text-slate-900 dark:text-slate-100"
          />
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

      <!-- 种子色选择 -->
      <div class="space-y-3 pt-2">
        <div class="flex items-center justify-between">
          <label class="text-xs font-semibold text-slate-500 block">
            M3 种子色 (Seed Color) 动态生成语义色盘
          </label>
          <div class="flex items-center gap-2">
            <span class="text-xs text-slate-500">提取 Windows 系统强调色</span>
            <md-switch :selected="useAccent" @change="handleToggleAccent" />
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <button
            v-for="c in PRESET_SEED_COLORS"
            :key="c.hex"
            @click="handleSelectSeed(c.hex)"
            class="flex items-center gap-2 px-3 py-1.5 rounded-xl border text-xs font-medium transition-all"
            :class="[
              currentSeed.toLowerCase() === c.hex.toLowerCase()
                ? 'border-primary bg-primary/10 shadow-sm'
                : 'border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60',
            ]"
          >
            <span class="w-3.5 h-3.5 rounded-full border border-black/10 shrink-0" :style="{ backgroundColor: c.hex }" />
            <span class="text-slate-800 dark:text-slate-200">{{ c.name }}</span>
          </button>

          <!-- 自定义调色盘 -->
          <div class="flex items-center gap-2 px-3 py-1 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60">
            <input
              type="color"
              :value="currentSeed"
              @input="handleCustomSeedChange"
              class="w-6 h-6 rounded cursor-pointer border-0 bg-transparent"
            />
            <span class="text-xs font-mono text-slate-600 dark:text-slate-300">{{ currentSeed }}</span>
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

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
            当极端异常发生导致系统网卡未还原时，一键从持久化快照完全还原原生 DNS。
          </p>
          <div v-if="restoreMessage" class="p-3 rounded-lg bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 text-xs font-semibold">
            {{ restoreMessage }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
