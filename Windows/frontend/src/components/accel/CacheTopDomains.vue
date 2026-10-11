<script setup lang="ts">
import { computed } from 'vue';
import type { CacheDomainStat } from '../../api/types';
import { formatClockTime } from '../../utils/format';

const props = defineProps<{
  topDomains: CacheDomainStat[];
}>();

const maxTopHits = computed(() => {
  if (props.topDomains.length === 0) return 1;
  return Math.max(...props.topDomains.map((d) => d.hitCount), 1);
});
</script>

<template>
  <div class="p-6 rounded-md bg-surface-card border border-surface-border space-y-4">
    <div class="flex items-center justify-between gap-3">
      <h3 class="section-title">高频访问网址排行</h3>
      <span class="text-[11px] text-text-muted">访问次数最多的前 10 个网址</span>
    </div>

    <div v-if="topDomains.length === 0" class="py-8 text-center text-xs text-text-muted">
      暂无访问记录
    </div>

    <div v-else class="space-y-2.5">
      <div
        v-for="(item, idx) in topDomains"
        :key="item.domain + item.qtype"
        class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub flex items-center justify-between gap-3 text-xs"
      >
        <!-- 排名与域名 -->
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="w-5 h-5 rounded-full flex items-center justify-center font-bold font-mono text-[10px]"
            :class="idx < 3 ? 'bg-brand-primary text-surface-card' : 'bg-surface-hover text-text-sub'"
          >
            {{ idx + 1 }}
          </span>
          <span class="font-mono font-medium text-text-main truncate" :title="item.domain">
            {{ item.domain }}
          </span>
          <span class="px-1.5 py-0.5 rounded text-[10px] font-mono bg-surface-card border border-surface-border text-text-sub">
            {{ item.qtype }}
          </span>
        </div>

        <!-- 频次柱状进度与命中数 -->
        <div class="flex items-center gap-3 shrink-0">
          <div class="w-20 md:w-28 bg-surface-card border border-surface-border rounded-full h-1.5 overflow-hidden hidden sm:block">
            <div
              class="bg-status-warning h-full rounded-full"
              :style="{ width: `${(item.hitCount / maxTopHits) * 100}%` }"
            ></div>
          </div>
          <span class="font-mono font-bold text-text-main min-w-8 text-right">
            {{ item.hitCount }} 次
          </span>
          <span class="text-[10px] text-text-muted min-w-14 text-right">
            {{ item.lastHitAt > 0 ? formatClockTime(item.lastHitAt) : '未命中' }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
