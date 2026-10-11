<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue';
import { ipc } from '../../api/ipc';
import type { WebSocketEvent, QueryEventData } from '../../api/types';
import M3Icon from '../M3Icon.vue';
import { formatClockTimeMs } from '../../utils/format';

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

const queryTypes = ['ALL', 'A', 'AAAA', 'HTTPS', 'CNAME', 'PTR', 'TXT'] as const;
const statusOptions = ['ALL', 'NOERROR', 'NXDOMAIN', 'SERVFAIL'] as const;

const filteredLogs = computed(() => {
  return logs.value.filter((item) => {
    if (onlyBlocked.value && !item.blocked) {
      return false;
    }
    if (searchFilter.value) {
      const q = searchFilter.value.toLowerCase();
      if (!item.domain.toLowerCase().includes(q) && !(item.clientIP || '').toLowerCase().includes(q)) {
        return false;
      }
    }
    if (selectedType.value !== 'ALL' && item.qtype !== selectedType.value) {
      return false;
    }
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
  <div class="flex flex-col space-y-4 select-none">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 shrink-0">
      <div class="flex items-baseline gap-2.5 min-w-0">
        <h2 class="section-title shrink-0">实时查询流</h2>
        <span class="font-mono text-[12px] text-text-muted shrink-0">
          {{ filteredLogs.length }} 条
        </span>
        <span v-if="!isPaused" class="flex items-center gap-1.5 text-[12px] text-text-muted shrink-0">
          <span class="w-1.5 h-1.5 rounded-full bg-accent-seal seal-pulse" />
          监听中
        </span>
      </div>

      <!-- 操作按钮组 -->
      <div class="flex items-center gap-2 shrink-0">
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
    <div class="app-panel flex flex-wrap items-center gap-2.5 p-2.5 shrink-0">
      <!-- 搜索框 -->
      <div class="relative flex-1 min-w-[200px]">
        <M3Icon name="search" :size="16" class="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" />
        <input
          v-model="searchFilter"
          type="text"
          placeholder="搜索网址或客户端 IP..."
          class="w-full pl-9 pr-4 h-[28px] rounded-md border border-surface-border-sub bg-surface-card-sub font-mono text-[12px] focus:outline-none focus:border-accent-seal text-text-main placeholder:text-text-muted"
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
          :class="onlyBlocked ? '!bg-accent-seal !text-white !border-accent-seal' : '!text-accent-seal !border-accent-seal/40'"
        >
          <M3Icon name="block" :size="14" />
          <span>仅看已拦截</span>
        </button>
      </div>
    </div>

    <!-- 实时日志滚动列表 -->
    <div
      ref="logContainer"
      class="app-panel overflow-y-auto p-2 space-y-0.5 font-mono text-[12px] h-[clamp(340px,58vh,680px)]"
    >
      <div
        v-if="filteredLogs.length === 0"
        class="h-full flex flex-col items-center justify-center p-12 text-text-muted gap-2"
      >
        <M3Icon name="logs" :size="30" class="opacity-40 text-text-muted" />
        <span>暂无符合条件的访问记录，上网浏览时将在此实时显示…</span>
      </div>

      <div
        v-for="item in filteredLogs"
        :key="item.id"
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-1.5 px-2.5 py-2 rounded-md border-l-2 transition-colors"
        :class="
          item.blocked
            ? 'border-accent-seal bg-accent-seal-bg'
            : 'border-transparent hover:bg-surface-hover/70'
        "
      >
        <div class="flex items-center gap-2.5 overflow-hidden">
          <!-- 拦截标识 -->
          <span
            v-if="item.blocked"
            class="px-1.5 py-0.5 rounded-sm bg-accent-seal text-white font-bold text-[10px] shrink-0"
            :title="`安全拦截: ${item.filterRule || item.filterReason || '已拦截'}`"
          >
            拦截
          </span>

          <!-- 状态色标 -->
          <span
            class="flex items-center gap-1.5 shrink-0 text-[11px]"
            :class="item.success ? 'text-status-success' : 'text-status-error'"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-current" />
            {{ item.rcode === 'NXDOMAIN' ? '不存在' : !item.success || item.rcode === 'SERVFAIL' ? '失败' : '成功' }}
          </span>

          <!-- 查询类型 -->
          <span class="text-text-muted shrink-0">{{ item.qtype || 'A' }}</span>

          <!-- 域名 -->
          <span
            class="font-semibold text-text-main truncate"
            :class="item.blocked ? 'line-through decoration-accent-seal/50' : ''"
            :title="item.domain"
          >
            {{ item.domain }}
          </span>
        </div>

        <div class="flex items-center gap-3 text-text-muted shrink-0 text-[11px]">
          <span class="flex items-center gap-1.5">
            <span
              v-if="item.clientIP && item.clientIP !== '127.0.0.1' && item.clientIP !== '::1'"
              class="px-1 py-0.5 rounded-sm text-[10px] border border-accent-seal/40 text-accent-seal"
            >
              局域网
            </span>
            <span>{{ item.clientIP || '127.0.0.1' }}</span>
          </span>
          <span
            class="text-text-sub"
            :class="item.durationMs > 100 ? 'text-status-warning' : ''"
          >
            {{ item.durationMs.toFixed(1) }} ms
          </span>
          <span>{{ formatClockTimeMs(item.timestamp) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
