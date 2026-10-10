<script setup lang="ts">
import { ref, computed } from 'vue';
import type { PortCheckResult } from '../api/types';
import AppModal from './AppModal.vue';
import M3Icon from './M3Icon.vue';

const props = defineProps<{
  open: boolean;
  conflictResult: PortCheckResult | null;
  recheckError?: string;
  rechecking?: boolean;
  autofixing?: boolean;
  allowLANDowngradable?: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'resolved'): void;
  (e: 'autofix'): void;
  (e: 'downgradeLAN'): void;
}>();

const copying = ref(false);

const isAutofixAvailable = computed(() => {
  return Boolean(props.conflictResult?.canAutofix || props.conflictResult?.hasICS);
});

async function copyCommand(cmd: string) {
  try {
    await navigator.clipboard.writeText(cmd);
    copying.value = true;
    setTimeout(() => {
      copying.value = false;
    }, 2000);
  } catch (err) {
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

      <!-- 自动修复优先引导模块 -->
      <div
        v-if="isAutofixAvailable"
        class="rounded-md border border-brand-primary/25 bg-brand-container/50 p-3.5 space-y-2.5"
      >
        <div class="flex items-center justify-between gap-2 flex-wrap">
          <div class="flex items-center gap-2 font-semibold text-brand-primary">
            <M3Icon name="bolt" :size="18" />
            <span>推荐处置方案：一键自动修复</span>
          </div>
          <button
            type="button"
            @click="emit('autofix')"
            :disabled="autofixing || rechecking"
            class="app-btn-primary app-btn-compact text-xs font-semibold shrink-0"
          >
            <M3Icon :name="autofixing ? 'refresh' : 'bolt'" :size="13" :class="autofixing ? 'animate-spin' : ''" />
            <span>{{ autofixing ? '正在停止服务并拉起...' : '一键自动修复并启动' }}</span>
          </button>
        </div>
        <p class="text-xs text-text-sub leading-relaxed">
          谛听后台服务具备 Windows 管理员特权，可直接调用服务控制管理器 (SCM) 自动停止并禁用冲突的 <span class="font-mono font-bold text-text-main">Windows ICS (SharedAccess)</span> 服务，解决后自动重试并拉起 DNS，无需手动打开管理员 CMD。
        </p>
      </div>

      <!-- 局域网模式降级引导模块 -->
      <div
        v-if="allowLANDowngradable"
        class="rounded-md border border-surface-border-sub bg-surface-card-sub p-3 space-y-2"
      >
        <div class="flex items-center justify-between gap-2 flex-wrap">
          <div class="text-xs font-semibold text-text-main flex items-center gap-1.5">
            <M3Icon name="router" :size="15" />
            <span>替代方案：降级为仅本机回环监听</span>
          </div>
          <button
            type="button"
            @click="emit('downgradeLAN')"
            :disabled="autofixing || rechecking"
            class="app-btn-secondary app-btn-compact text-xs shrink-0"
          >
            <span>切换为本机监听并启动</span>
          </button>
        </div>
        <p class="text-[11px] text-text-muted leading-relaxed">
          若暂不需要为局域网内的其他设备提供 DNS，可一键关闭局域网共享模式，仅监听 127.0.0.1:53，直接避开系统 ICS 服务的局域网广播冲突。
        </p>
      </div>

      <!-- 冲突实体详情列表 -->
      <div v-if="conflictResult?.conflicts && conflictResult.conflicts.length > 0" class="space-y-3">
        <div
          v-for="(item, idx) in conflictResult.conflicts"
          :key="idx"
          class="rounded-md border border-surface-border-sub bg-surface-card-sub p-3.5 space-y-2.5"
        >
          <div class="flex items-center justify-between flex-wrap gap-2">
            <div class="flex items-center gap-2 font-semibold text-text-main">
              <span class="px-2 py-0.5 rounded text-[11px] font-mono font-bold border border-status-warning/40 text-status-warning">
                {{ item.protocol }} {{ item.localAddress }}
              </span>
              <span>{{ item.isICS ? 'Windows 网络连接共享服务 (ICS)' : (item.processName || '未知程序') }}</span>
            </div>
            <span class="text-[11px] text-text-muted font-mono">
              PID: {{ item.pid }}
            </span>
          </div>

          <!-- ICS 手动排查指引备选 -->
          <div v-if="item.isICS || item.serviceName === 'SharedAccess'" class="space-y-2 text-xs">
            <p class="text-text-sub leading-relaxed">
              若希望手动操作，可在管理员 CMD 中执行以下命令停止服务：
            </p>
            <div class="flex items-center justify-between gap-2 p-2 rounded-md bg-surface-card border border-surface-border font-mono text-[11px]">
              <span class="text-text-main select-all">sc stop SharedAccess</span>
              <button
                type="button"
                @click="copyCommand('sc stop SharedAccess')"
                class="app-btn-secondary app-btn-compact shrink-0"
              >
                <M3Icon :name="copying ? 'check' : 'content_copy'" :size="12" />
                <span>{{ copying ? '已复制' : '复制命令' }}</span>
              </button>
            </div>
            <p class="text-[11px] text-text-muted">
              提示：可按 <kbd class="px-1 py-0.5 rounded bg-surface-border text-text-main font-mono">Win + R</kbd> 打开 <span class="font-mono">services.msc</span>，将 <span class="font-medium text-text-main">Internet Connection Sharing (ICS)</span> 服务启动类型设为“禁用”。
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

      <!-- 综合诊断建议兜底 -->
      <div v-else-if="conflictResult?.diagnostic" class="p-3 rounded-md bg-surface-card-sub border border-surface-border-sub text-xs space-y-1">
        <div class="font-semibold text-status-warning">诊断建议</div>
        <p class="text-text-sub whitespace-pre-line">{{ conflictResult.diagnostic }}</p>
      </div>

      <!-- 重新检测或操作报错提示 -->
      <div v-if="recheckError" class="p-2.5 rounded-md bg-status-error-bg border border-status-error/20 text-xs text-status-error flex items-center gap-1.5">
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
        v-if="isAutofixAvailable"
        type="button"
        @click="emit('autofix')"
        :disabled="autofixing || rechecking"
        class="app-btn-primary"
      >
        <M3Icon :name="autofixing ? 'refresh' : 'bolt'" :size="14" :class="autofixing ? 'animate-spin' : ''" />
        <span>{{ autofixing ? '正在修复并启动...' : '一键自动修复并启动' }}</span>
      </button>

      <button
        type="button"
        @click="emit('resolved')"
        :disabled="rechecking || autofixing"
        :class="isAutofixAvailable ? 'app-btn-secondary' : 'app-btn-primary'"
      >
        <M3Icon :name="rechecking ? 'refresh' : 'sync'" :size="14" :class="rechecking ? 'animate-spin' : ''" />
        <span>{{ rechecking ? '正在检测并启动...' : (isAutofixAvailable ? '手动解决后重测' : '已解决，重新检测并启动') }}</span>
      </button>
    </template>
  </AppModal>
</template>
