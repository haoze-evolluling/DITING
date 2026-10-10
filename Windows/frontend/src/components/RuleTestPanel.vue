<script setup lang="ts">
import { ref } from 'vue';
import { ipc } from '../api/ipc';
import type { CheckHostResult } from '../api/types';
import M3Icon from './M3Icon.vue';

const emit = defineEmits<{
  (e: 'error', message: string): void;
}>();

const testDomain = ref('');
const testQType = ref('A');
const testResult = ref<CheckHostResult | null>(null);
const testing = ref(false);

async function runTest() {
  if (!testDomain.value.trim()) return;
  try {
    testing.value = true;
    testResult.value = await ipc.checkHost(testDomain.value.trim(), testQType.value);
  } catch (err: any) {
    emit('error', err?.message || '规则检测异常');
  } finally {
    testing.value = false;
  }
}
</script>

<template>
  <div class="p-6 rounded-md bg-surface-card border border-surface-border space-y-4">
    <div>
      <h3 class="section-title">网址拦截模拟测试</h3>
      <p class="text-xs text-text-sub mt-1">输入任意网址或域名，即可快速检测其是否会被防护规则拦截以及原因</p>
    </div>

    <div class="flex flex-col md:flex-row gap-3 items-center">
      <input
        v-model="testDomain"
        placeholder="例如: ad.example.com"
        @keyup.enter="runTest"
        class="flex-1 h-9 px-4 rounded-md border border-surface-border bg-surface-card-sub text-xs focus:outline-none focus:border-accent-seal text-text-main placeholder:text-text-muted"
      />
      <select
        v-model="testQType"
        class="h-9 px-3 rounded-md border border-surface-border bg-surface-card-sub text-xs focus:outline-none focus:border-accent-seal text-text-main"
      >
        <option value="A">IPv4 地址 (A 记录)</option>
        <option value="AAAA">IPv6 地址 (AAAA 记录)</option>
        <option value="ANY">全部记录类型 (ANY)</option>
      </select>
      <button type="button" @click="runTest" :disabled="testing || !testDomain.trim()" class="app-btn-primary">
        <M3Icon name="search" :size="16" />
        <span>{{ testing ? '检测中...' : '立即测试' }}</span>
      </button>
    </div>

    <div
      v-if="testResult"
      class="p-5 rounded-md border text-sm"
      :class="testResult.blocked ? 'bg-status-error-bg border-status-error/30' : testResult.action === 'allow' ? 'bg-status-success-bg border-status-success/30' : 'bg-surface-card-sub border-surface-border-sub'"
    >
      <div class="flex items-center gap-3">
        <span
          class="px-2.5 py-1 rounded-full text-xs font-bold text-white"
          :class="testResult.blocked ? 'bg-accent-seal' : testResult.action === 'allow' ? 'bg-status-success' : 'bg-text-muted'"
        >
          {{ testResult.blocked ? '已拦截 (阻止访问)' : testResult.action === 'allow' ? '已放行 (信任名单)' : '未命中规则 (正常访问)' }}
        </span>
        <span class="font-mono font-bold text-text-main">{{ testDomain }}</span>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-3 mt-4 text-xs">
        <div>
          <span class="text-text-muted">命中的规则: </span>
          <span class="font-mono text-text-main font-semibold">{{ testResult.matchedRule || '无' }}</span>
        </div>
        <div>
          <span class="text-text-muted">所属规则库: </span>
          <span class="font-medium text-text-main">{{ testResult.listName || '无' }}</span>
        </div>
        <div>
          <span class="text-text-muted">处理原因: </span>
          <span class="font-medium text-text-main">{{ testResult.reason || '未命中规则' }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
