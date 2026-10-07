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
const autoScroll = ref(true);
const searchFilter = ref('');
const selectedType = ref('ALL');
const selectedStatus = ref('ALL');

const logContainer = ref<HTMLElement | null>(null);
let unsubEvents: (() => void) | null = null;
let idCounter = 0;

const queryTypes = ['ALL', 'A', 'AAAA', 'HTTPS', 'CNAME', 'PTR', 'TXT'];
const statusOptions = ['ALL', 'NOERROR', 'NXDOMAIN', 'SERVFAIL'];

const filteredLogs = computed(() => {
  return logs.value.filter((item) => {
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
  // 保留最新 500 条记录
  if (logs.value.length > 500) {
    logs.value.pop();
  }

  if (autoScroll.value && logContainer.value) {
    nextTick(() => {
      // 保持置顶滚动
      if (logContainer.value) {
        logContainer.value.scrollTop = 0;
      }
    });
  }
}

function clearLogs() {
  logs.value = [];
}

function togglePause() {
  isPaused.value = !isPaused.value;
}

function formatTime(ts: number) {
  const d = new Date(ts);
  return d.toTimeString().split(' ')[0] + '.' + String(d.getMilliseconds()).padStart(3, '0');
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
  <div class="space-y-4 pb-12 flex flex-col h-[calc(100vh-140px)]">
    <!-- 头部工具栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 shrink-0">
      <div>
        <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100 flex items-center gap-2">
          实时 DNS 解析日志
          <span class="text-xs font-semibold px-2 py-0.5 rounded-full bg-slate-200 dark:bg-slate-800 text-slate-600 dark:text-slate-400">
            {{ filteredLogs.length }} 条记录
          </span>
        </h2>
        <p class="text-sm text-slate-500 dark:text-slate-400">
          基于 WebSocket 实时通道接收来自 127.0.0.1:53 的 DNS 查询事件。
        </p>
      </div>

      <!-- 操作按钮组 -->
      <div class="flex items-center gap-2">
        <md-outlined-button @click="togglePause">
          <M3Icon :name="isPaused ? 'play_arrow' : 'pause'" slot="icon" :size="16" />
          {{ isPaused ? '继续滚动' : '暂停滚屏' }}
        </md-outlined-button>

        <md-outlined-button @click="clearLogs">
          <M3Icon name="delete" slot="icon" :size="16" />
          清空记录
        </md-outlined-button>
      </div>
    </div>

    <!-- 检索与过滤条 (Filter Chips & Search) -->
    <div class="flex flex-wrap items-center gap-3 p-3 rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 shadow-sm backdrop-blur shrink-0">
      <!-- 搜索框 -->
      <div class="relative flex-1 min-w-[200px]">
        <M3Icon name="search" :size="18" class="absolute left-3 top-2.5 text-slate-400" />
        <input
          v-model="searchFilter"
          type="text"
          placeholder="检索域名或客户端 IP..."
          class="w-full pl-9 pr-4 py-1.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/80 text-xs focus:outline-none focus:ring-2 focus:ring-primary/40 text-slate-900 dark:text-slate-100 placeholder:text-slate-400"
        />
      </div>

      <!-- QType Chips -->
      <div class="flex items-center gap-1.5 overflow-x-auto py-1">
        <button
          v-for="t in queryTypes"
          :key="t"
          @click="selectedType = t"
          class="px-2.5 py-1 rounded-lg text-xs font-semibold transition-all duration-150 select-none"
          :class="[
            selectedType === t
              ? 'bg-primary text-on-primary shadow-sm'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-700',
          ]"
        >
          {{ t }}
        </button>
      </div>

      <!-- Status Chips -->
      <div class="flex items-center gap-1.5 overflow-x-auto py-1 border-l border-slate-200 dark:border-slate-800 pl-3">
        <button
          v-for="s in statusOptions"
          :key="s"
          @click="selectedStatus = s"
          class="px-2.5 py-1 rounded-lg text-xs font-semibold transition-all duration-150 select-none"
          :class="[
            selectedStatus === s
              ? 'bg-slate-800 dark:bg-slate-200 text-white dark:text-slate-900'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-700',
          ]"
        >
          {{ s }}
        </button>
      </div>
    </div>

    <!-- 实时日志滚动列表 -->
    <div
      ref="logContainer"
      class="flex-1 overflow-y-auto rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 shadow-sm backdrop-blur p-3 space-y-2 font-mono text-xs"
    >
      <div
        v-if="filteredLogs.length === 0"
        class="h-full flex flex-col items-center justify-center p-12 text-slate-400"
      >
        <M3Icon name="logs" :size="36" class="mb-2 opacity-50" />
        <span>暂无匹配的 DNS 查询记录，发起域名访问后将自动实时呈现...</span>
      </div>

      <div
        v-for="item in filteredLogs"
        :key="item.id"
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-3 rounded-xl border border-slate-100 dark:border-slate-800/50 bg-slate-50/60 dark:bg-slate-950/30 hover:bg-slate-100/80 dark:hover:bg-slate-800/40 transition-colors"
      >
        <div class="flex items-center gap-3 overflow-hidden">
          <!-- 状态色标 -->
          <span
            class="px-2 py-0.5 rounded-md font-bold text-[10px] shrink-0"
            :class="[
              item.success
                ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400'
                : 'bg-rose-500/15 text-rose-600 dark:text-rose-400',
            ]"
          >
            {{ item.rcode || (item.success ? 'NOERROR' : 'SERVFAIL') }}
          </span>

          <!-- 查询类型 -->
          <span class="px-2 py-0.5 rounded-md bg-sky-500/15 text-sky-600 dark:text-sky-400 font-bold text-[10px] shrink-0">
            {{ item.qtype || 'A' }}
          </span>

          <!-- 域名 -->
          <span class="font-semibold text-slate-900 dark:text-slate-100 truncate" :title="item.domain">
            {{ item.domain }}
          </span>
        </div>

        <div class="flex items-center gap-4 text-slate-500 dark:text-slate-400 shrink-0 text-[11px]">
          <span>IP: {{ item.clientIP || '127.0.0.1' }}</span>
          <span class="font-semibold" :class="item.durationMs > 100 ? 'text-amber-500' : 'text-slate-600 dark:text-slate-300'">
            {{ item.durationMs.toFixed(1) }} ms
          </span>
          <span class="text-slate-400">{{ formatTime(item.timestamp) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
