<script setup lang="ts">
import { ref } from 'vue';
import type { PortCheckResult } from '../api/types';
import AppModal from './AppModal.vue';
import M3Icon from './M3Icon.vue';

const props = defineProps<{
  open: boolean;
  conflictResult: PortCheckResult | null;
  recheckError?: string;
  rechecking?: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'resolved'): void;
}>();

const copying = ref(false);

async function copyCommand(cmd: string) {
  try {
    await navigator.clipboard.writeText(cmd);
    copying.value = true;
    setTimeout(() => {
      copying.value = false;
    }, 2000);
  } catch (err) {
    // Fallback if clipboard API fails
    const textarea = document.createElement('textarea');
    textarea.value = cmd;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    copying.value = true;
    setTimeout(() => {
      copying.value = false;
    }, 2000);
  }
}

function handleClose() {
  emit('close');
}
</script>

<template>
  <AppModal
    :open="open"
    @close="handleClose"
    type="alert"
    maxWidth="max-w-xl"
  >
    <template #headline>
      <div class="flex items-center gap-2.5 text-status-warning font-bold">
        <M3Icon name="warning" :size="24" />
        <span class="text-base sm:text-lg">DNS 端口 (53) 占用冲突诊断与指引</span>
      </div>
    </template>

    <div class="space-y-4 text-xs sm:text-sm text-text-sub">
      <p class="leading-relaxed">
        本地 DNS 加速引擎需要绑定标准端口 <span class="font-mono font-semibold text-text-main">53 (UDP/TCP)</span>。当前检测到该端口正被其他进程或 Windows 系统服务占用，导致服务无法正常启动。
      </p>

      <!-- 冲突实体列表 -->
      <div v-if="conflictResult?.conflicts && conflictResult.conflicts.length > 0" class="space-y-3">
        <div
          v-for="(item, idx) in conflictResult.conflicts"
          :key="idx"
          class="rounded-xl border border-surface-border-sub bg-surface-card-sub p-3.5 space-y-2.5"
        >
          <div class="flex items-center justify-between flex-wrap gap-2">
            <div class="flex items-center gap-2 font-semibold text-text-main">
              <span class="px-2 py-0.5 rounded text-[11px] font-mono font-bold bg-amber-500/15 text-amber-600 dark:text-amber-400 border border-amber-500/20">
                {{ item.protocol }} {{ item.localAddress }}
              </span>
              <span>{{ item.isICS ? 'Windows 网络连接共享服务' : (item.processName || '未知程序') }}</span>
            </div>
            <span class="text-[11px] text-text-muted font-mono">
              PID: {{ item.pid }}
            </span>
          </div>

          <!-- ICS 专项指引 -->
          <div v-if="item.isICS || item.serviceName === 'SharedAccess'" class="space-y-2 text-xs">
            <p class="text-text-sub leading-relaxed">
              Windows 网络连接共享 (ICS / SharedAccess) 会在后台占用 UDP 53 端口。如不需要向其他局域网电脑共享网络，建议停止并禁用该服务：
            </p>
            <div class="flex items-center justify-between gap-2 p-2 rounded-lg bg-surface-card border border-surface-border font-mono text-[11px]">
              <span class="text-text-main select-all">sc stop SharedAccess</span>
              <button
                type="button"
                @click="copyCommand('sc stop SharedAccess')"
                class="app-btn-secondary app-btn-compact shrink-0"
              >
                <M3Icon :name="copying ? 'check' : 'copy'" :size="12" />
                <span>{{ copying ? '已复制' : '复制命令' }}</span>
              </button>
            </div>
            <p class="text-[11px] text-text-muted">
              提示：可按 <kbd class="px-1 py-0.5 rounded bg-surface-border text-text-main font-mono">Win + R</kbd> 打开 <span class="font-mono">services.msc</span>，将 <span class="font-medium text-text-main">Internet Connection Sharing (ICS)</span> 服务设置为“禁用”以永久防止冲突。
            </p>
          </div>

          <!-- 其他通用进程指引 -->
          <div v-else class="space-y-1.5 text-xs">
            <p class="text-text-sub leading-relaxed">
              外部程序 <span class="font-semibold text-text-main font-mono">{{ item.processName }}</span> 正在占用端口。
            </p>
            <p class="text-[11px] text-text-muted leading-relaxed">
              排查引导：可按 <kbd class="px-1 py-0.5 rounded bg-surface-border text-text-main font-mono">Ctrl + Shift + Esc</kbd> 打开任务管理器，在“详细信息”列表中根据 PID (<span class="font-mono text-text-main font-semibold">{{ item.pid }}</span>) 找到该程序并结束，或修改该程序的监听端口配置。
            </p>
          </div>
        </div>
      </div>

      <!-- 兜底提示 -->
      <div v-else-if="conflictResult?.diagnostic" class="p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub text-xs space-y-1">
        <div class="font-semibold text-status-warning">诊断建议</div>
        <p class="text-text-sub whitespace-pre-line">{{ conflictResult.diagnostic }}</p>
      </div>

      <!-- 重新检测失败提示 -->
      <div v-if="recheckError" class="p-2.5 rounded-lg bg-status-error-bg border border-status-error/20 text-xs text-status-error flex items-center gap-1.5">
        <M3Icon name="error" :size="14" />
        <span>{{ recheckError }}</span>
      </div>
    </div>

    <template #actions>
      <button
        type="button"
        @click="handleClose"
        class="app-btn-secondary"
      >
        稍后处理
      </button>
      <button
        type="button"
        @click="emit('resolved')"
        :disabled="rechecking"
        class="app-btn-primary"
      >
        <M3Icon :name="rechecking ? 'hourglass' : 'refresh'" :size="14" :class="rechecking ? 'animate-spin' : ''" />
        <span>{{ rechecking ? '正在检测并启动...' : '已解决，重新检测并启动' }}</span>
      </button>
    </template>
  </AppModal>
</template>
