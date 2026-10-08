<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue';
import { ipc } from '../api/ipc';
import type { WebSocketEvent, QueryEventData } from '../api/types';
import M3Icon from '../components/M3Icon.vue';

interface LogItem extends QueryEventData {
  id: string;
  timestamp: number;
}

const logs = ref<LogItem[]>([]);
const isPaused = ref(false);
const searchFilter = ref('');
const selectedType = ref('ALL');
const selectedStatus = ref('ALL');
const onlyBlocked = ref(false);

const logContainer = ref<HTMLElement | null>(null);
let unsubEvents: (() => void) | null = null;
let idCounter = 0;

const queryTypes = ['ALL', 'A', 'AAAA', 'HTTPS', 'CNAME', 'PTR', 'TXT'];
const statusOptions = ['ALL', 'NOERROR', 'NXDOMAIN', 'SERVFAIL'];

const filteredLogs = computed(() => {
  return logs.value.filter((item) => {
    // 拦截过滤
    if (onlyBlocked.value && !item.blocked) {
      return false;
    }
    // 域名搜索
    if (searchFilter.value) {
      const q = searchFilter.value.toLowerCase();
      if (!item.domain.toLowerCase().includes(q) && !item.clientIP.toLowerCase().includes(q)) {
        return false;
      }
    }
    // 类型过滤
    if (selectedType.value !== 'ALL' && item.qtype !== selectedType.value) {
      return false;
    }
    // 状态过滤
    if (selectedStatus.value !== 'ALL') {
      const rcode = item.rcode || (item.success ? 'NOERROR' : 'SERVFAIL');
      if (rcode !== selectedStatus.value) {
        return false;
      }
    }
    return true;
  });
});

function handleNewQuery(data: QueryEventData, timestamp: number) {
  if (isPaused.value) return;

  const item: LogItem = {
    ...data,
    id: `log-${++idCounter}`,
    timestamp: timestamp || Date.now(),
  };

  logs.value.unshift(item);
  if (logs.value.length > 500) {
    logs.value.pop();
  }

  nextTick(() => {
    if (logContainer.value && !isPaused.value) {
      logContainer.value.scrollTop = 0;
    }
  });
}

function clearLogs() {
  logs.value = [];
}

function togglePause() {
  isPaused.value = !isPaused.value;
}

function formatTime(timestamp: number): string {
  const d = new Date(timestamp);
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${d.getMilliseconds().toString().padStart(3, '0')}`;
}

onMounted(() => {
  unsubEvents = ipc.onEvent((event: WebSocketEvent) => {
    if (event.type === 'query') {
      handleNewQuery(event.data, event.timestamp);
    }
  });
});

onUnmounted(() => {
  if (unsubEvents) unsubEvents();
});
</script>

<template>
  <div class="h-full flex flex-col space-y-4 pb-6 select-none">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 shrink-0">
      <div>
        <h2 class="text-2xl font-bold tracking-tight text-text-main flex items-center gap-2">
          网络访问与解析记录
          <span class="text-xs font-semibold px-2 py-0.5 rounded-full bg-surface-card-sub text-text-sub border border-surface-border-sub">
            {{ filteredLogs.length }} 条记录
          </span>
        </h2>
        <p class="text-sm text-text-sub">
          实时记录本机的域名访问、解析耗时以及安全拦截情况。
        </p>
      </div>

      <!-- 操作按钮组 -->
      <div class="flex items-center gap-2">
        <button
          type="button"
          @click="togglePause"
          class="app-btn-secondary"
        >
          <M3Icon :name="isPaused ? 'play_arrow' : 'pause'" :size="16" />
          <span>{{ isPaused ? '继续滚动' : '暂停滚屏' }}</span>
        </button>

        <button
          type="button"
          @click="clearLogs"
          class="app-btn-secondary"
        >
          <M3Icon name="delete" :size="16" />
          <span>清空记录</span>
        </button>
      </div>
    </div>

    <!-- 检索与过滤条 (Filter Chips & Search) -->
    <div class="flex flex-wrap items-center gap-3 p-3 rounded-2xl border border-surface-border bg-surface-card shadow-xs shrink-0 transition-colors">
      <!-- 搜索框 -->
      <div class="relative flex-1 min-w-[200px]">
        <M3Icon name="search" :size="16" class="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" />
        <input
          v-model="searchFilter"
          type="text"
          placeholder="搜索网址或客户端 IP..."
          class="w-full pl-9 pr-4 h-[30px] rounded-lg border border-surface-border-sub bg-surface-card-sub text-xs focus:outline-none focus:ring-2 focus:ring-brand-primary/40 text-text-main placeholder:text-text-muted"
        />
      </div>

      <!-- QType Chips -->
      <div class="flex items-center gap-1.5 overflow-x-auto py-0.5">
        <button
          v-for="t in queryTypes"
          :key="t"
          @click="selectedType = t"
          class="app-btn-chip"
          :class="{ active: selectedType === t }"
        >
          {{ t === 'ALL' ? '全部类型' : t }}
        </button>
      </div>

      <!-- Status Chips -->
      <div class="flex items-center gap-1.5 overflow-x-auto py-0.5 border-l border-surface-border pl-3">
        <button
          v-for="s in statusOptions"
          :key="s"
          @click="selectedStatus = s"
          class="app-btn-chip"
          :class="{ active: selectedStatus === s }"
        >
          {{ s === 'ALL' ? '全部状态' : s === 'NOERROR' ? '成功' : s === 'NXDOMAIN' ? '域名不存在' : '解析失败' }}
        </button>
      </div>

      <!-- 仅拦截过滤器 -->
      <div class="flex items-center border-l border-surface-border pl-3">
        <button
          @click="onlyBlocked = !onlyBlocked"
          class="app-btn-chip"
          :class="onlyBlocked ? '!bg-status-error !text-white !border-transparent shadow-xs' : '!text-status-error !bg-status-error-bg !border-status-error/30'"
        >
          <M3Icon name="block" :size="14" />
          <span>仅看已拦截</span>
        </button>
      </div>
    </div>

    <!-- 实时日志滚动列表 -->
    <div
      ref="logContainer"
      class="flex-1 overflow-y-auto rounded-2xl border border-surface-border bg-surface-card shadow-xs p-3 space-y-2 font-mono text-xs transition-colors"
    >
      <div
        v-if="filteredLogs.length === 0"
        class="h-full flex flex-col items-center justify-center p-12 text-text-muted"
      >
        <M3Icon name="logs" :size="36" class="mb-2 opacity-40 text-text-muted" />
        <span>暂无符合条件的访问记录，上网浏览时将在此实时显示...</span>
      </div>

      <div
        v-for="item in filteredLogs"
        :key="item.id"
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-3 rounded-xl border border-surface-border-sub bg-surface-card-sub hover:bg-surface-hover/70 transition-colors"
      >
        <div class="flex items-center gap-3 overflow-hidden">
          <!-- 拦截标识 -->
          <span
            v-if="item.blocked"
            class="px-2 py-0.5 rounded-md bg-status-error text-white font-bold text-[10px] shrink-0"
            :title="`安全拦截: ${item.filterRule || item.filterReason || '已拦截'}`"
          >
            已拦截
          </span>

          <!-- 状态色标 -->
          <span
            class="px-2 py-0.5 rounded-md font-bold text-[10px] shrink-0 border"
            :class="[
              item.success
                ? 'bg-status-success-bg text-status-success border-status-success/30'
                : 'bg-status-error-bg text-status-error border-status-error/30',
            ]"
          >
            {{ item.rcode === 'NXDOMAIN' ? '域名不存在' : !item.success || item.rcode === 'SERVFAIL' ? '解析失败' : '成功' }}
          </span>

          <!-- 查询类型 -->
          <span class="px-2 py-0.5 rounded-md bg-brand-container text-brand-primary font-bold text-[10px] shrink-0">
            {{ item.qtype || 'A' }}
          </span>

          <!-- 域名 -->
          <span class="font-semibold text-text-main truncate" :title="item.domain">
            {{ item.domain }}
          </span>
        </div>

        <div class="flex items-center gap-4 text-text-sub shrink-0 text-[11px]">
          <span class="flex items-center gap-1.5">
            <span
              v-if="item.clientIP && item.clientIP !== '127.0.0.1' && item.clientIP !== '::1'"
              class="px-1.5 py-0.5 rounded text-[10px] font-bold bg-brand-primary/10 text-brand-primary border border-brand-primary/30"
            >
              局域网
            </span>
            <span>来源: {{ item.clientIP || '127.0.0.1' }}</span>
          </span>
          <span class="font-semibold" :class="item.durationMs > 100 ? 'text-status-warning' : 'text-text-main'">
            {{ item.durationMs.toFixed(1) }} 毫秒
          </span>
          <span class="text-text-muted">{{ formatTime(item.timestamp) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
