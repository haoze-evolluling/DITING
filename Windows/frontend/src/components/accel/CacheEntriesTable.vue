<script setup lang="ts">
import { ref, computed } from 'vue';
import type { CacheEntryItem } from '../../api/types';
import M3Icon from '../M3Icon.vue';

const props = defineProps<{
  entries: CacheEntryItem[];
  totalCount: number;
}>();

const emit = defineEmits<{
  (e: 'search', query: string): void;
}>();

const searchQuery = ref('');
const statusFilter = ref<'all' | 'fresh' | 'stale' | 'negative'>('all');

const filterChips = [
  { id: 'all', label: '全部' },
  { id: 'fresh', label: '有效记录' },
  { id: 'stale', label: '应急备用' },
  { id: 'negative', label: '无效网址' },
] as const;

const filteredEntries = computed(() => {
  return props.entries.filter((item) => {
    if (statusFilter.value === 'fresh' && item.status !== 'fresh') return false;
    if (statusFilter.value === 'stale' && item.status !== 'stale') return false;
    if (statusFilter.value === 'negative' && !item.isNegative) return false;
    return true;
  });
});

function handleSearch() {
  emit('search', searchQuery.value.trim());
}
</script>

<template>
  <div class="p-6 rounded-md bg-surface-card border border-surface-border space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div class="flex items-center gap-2">
        <h3 class="section-title">
          已缓存域名列表 ({{ totalCount }} 条)
        </h3>
      </div>

      <div class="flex items-center gap-3">
        <!-- 搜索输入框 (高度与检索按钮保持严格等高 34px) -->
        <div class="relative w-64">
          <M3Icon name="search" :size="16" class="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" />
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索网址或记录类型..."
            @keyup.enter="handleSearch"
            class="w-full pl-9 pr-3 h-[34px] rounded-md border border-surface-border bg-surface-card-sub text-xs focus:outline-none focus:ring-2 focus:border-accent-seal text-text-main placeholder:text-text-muted font-mono"
          />
        </div>

        <button
          type="button"
          @click="handleSearch"
          class="app-btn-secondary"
        >
          <M3Icon name="search" :size="16" />
          <span>检索</span>
        </button>
      </div>
    </div>

    <!-- 状态过滤 Chips -->
    <div class="flex items-center gap-2">
      <button
        v-for="f in filterChips"
        :key="f.id"
        @click="statusFilter = f.id"
        class="app-btn-chip"
        :class="{ active: statusFilter === f.id }"
      >
        {{ f.label }}
      </button>
    </div>

    <!-- 条目列表 -->
    <div v-if="filteredEntries.length === 0" class="py-12 text-center text-xs text-text-muted">
      未匹配到符合条件的缓存条目
    </div>

    <div v-else class="overflow-x-auto">
      <table class="w-full text-left text-xs font-mono">
        <thead>
          <tr class="border-b border-surface-border text-text-muted">
            <th class="py-2.5 font-medium">网址 / 域名</th>
            <th class="py-2.5 font-medium">记录类型</th>
            <th class="py-2.5 font-medium">缓存状态</th>
            <th class="py-2.5 font-medium">剩余有效期</th>
            <th class="py-2.5 font-medium">初始有效期</th>
            <th class="py-2.5 font-medium">命中次数</th>
            <th class="py-2.5 font-medium">解析 IP</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-surface-border-sub">
          <tr v-for="entry in filteredEntries" :key="entry.domain + entry.qtype" class="hover:bg-surface-hover/50 transition-colors">
            <td class="py-2.5 font-bold text-text-main">{{ entry.domain }}</td>
            <td class="py-2.5 text-text-sub">{{ entry.qtype }}</td>
            <td class="py-2.5">
              <span v-if="entry.isNegative" class="px-2 py-0.5 rounded-full text-[10px] bg-status-error-bg text-status-error">无效网址</span>
              <span v-else-if="entry.status === 'fresh'" class="px-2 py-0.5 rounded-full text-[10px] bg-status-success-bg text-status-success">有效</span>
              <span v-else class="px-2 py-0.5 rounded-full text-[10px] bg-status-warning-bg text-status-warning">应急备用</span>
            </td>
            <td class="py-2.5 font-bold" :class="entry.remainingTtl > 0 ? 'text-text-main' : 'text-status-warning'">{{ entry.remainingTtl }}s</td>
            <td class="py-2.5 text-text-muted">{{ entry.originalTtl }}s</td>
            <td class="py-2.5 text-text-main font-bold">{{ entry.hitCount }}</td>
            <td class="py-2.5 text-text-sub max-w-xs truncate" :title="entry.ipList?.join(', ') || '无'">
              {{ entry.ipList && entry.ipList.length > 0 ? entry.ipList.join(', ') : '-' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
