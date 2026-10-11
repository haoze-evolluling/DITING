<script setup lang="ts">
import type { StatusResponse } from '../../api/types';
import type { NavTab } from '../../constants/navigation';
import M3Icon from '../M3Icon.vue';

defineProps<{
  status: StatusResponse | null;
  formatDnsMode: string;
  allowLAN: boolean;
  primaryLanIP: string;
  takeoverActive: boolean;
}>();

const emit = defineEmits<{
  (e: 'navigate', tab: NavTab): void;
}>();
</script>

<template>
  <div class="flex flex-col gap-3.5">
    <!-- 上游节点摘要 -->
    <div class="rounded-md border border-surface-border bg-surface-card p-4 transition-colors">
      <div class="flex items-center justify-between gap-2 mb-2.5">
        <div class="flex items-center gap-2 min-w-0">
          <M3Icon name="upstream" :size="18" class="text-text-main shrink-0" />
          <h3 class="font-semibold text-text-main text-sm truncate">DNS 服务</h3>
        </div>
        <button
          type="button"
          @click="emit('navigate', 'network')"
          class="app-btn-tonal app-btn-compact"
        >
          管理服务器
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">工作策略</div>
          <div class="text-xs font-semibold text-text-main truncate mt-0.5">
            {{ formatDnsMode }}
          </div>
        </div>
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">局域网服务</div>
          <div class="text-xs font-semibold truncate mt-0.5" :class="allowLAN ? 'text-status-success font-mono' : 'text-text-sub'">
            {{ allowLAN ? (primaryLanIP || '全网监听') : '仅本机' }}
          </div>
        </div>
      </div>
    </div>

    <!-- 智能缓存摘要 -->
    <div class="rounded-md border border-surface-border bg-surface-card p-4 transition-colors">
      <div class="flex items-center justify-between gap-2 mb-2.5">
        <div class="flex items-center gap-2 min-w-0">
          <M3Icon name="cache" :size="18" class="text-text-main shrink-0" />
          <h3 class="font-semibold text-text-main text-sm truncate">解析加速</h3>
        </div>
        <button
          type="button"
          @click="emit('navigate', 'accel')"
          class="app-btn-tonal app-btn-compact"
        >
          查看详情
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">缓存命中率</div>
          <div class="text-xs font-bold text-text-main font-mono mt-0.5">
            {{ ((status?.cache?.hitRatio || 0) * 100).toFixed(1) }}%
          </div>
        </div>
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">已存记录 / 容量</div>
          <div class="text-xs font-mono text-text-main truncate mt-0.5">
            {{ status?.cache?.entryCount || 0 }} / {{ status?.cache?.maxEntries || 4096 }}
          </div>
        </div>
      </div>
    </div>

    <!-- 规则防护摘要 -->
    <div class="rounded-md border border-surface-border bg-surface-card p-4 transition-colors">
      <div class="flex items-center justify-between gap-2 mb-2.5">
        <div class="flex items-center gap-2 min-w-0">
          <M3Icon name="shield" :size="18" class="text-text-main shrink-0" />
          <h3 class="font-semibold text-text-main text-sm truncate">规则拦截</h3>
        </div>
        <button
          type="button"
          @click="emit('navigate', 'rules')"
          class="app-btn-tonal app-btn-compact"
        >
          管理规则
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">请求拦截率</div>
          <div class="text-xs font-bold text-status-error font-mono mt-0.5">
            {{ (status?.filter?.blockRate || 0).toFixed(1) }}%
          </div>
        </div>
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">已拦截 / 规则数</div>
          <div class="text-xs font-mono text-text-main truncate mt-0.5">
            {{ status?.filter?.blockedQueries || 0 }} / {{ status?.filter?.totalRules || 0 }}
          </div>
        </div>
      </div>
    </div>

    <!-- 网卡接管简报 -->
    <div class="rounded-md border border-surface-border bg-surface-card p-4 transition-colors">
      <div class="flex items-center justify-between gap-2 mb-2.5">
        <div class="flex items-center gap-2 min-w-0">
          <M3Icon name="adapters" :size="18" class="text-text-main shrink-0" />
          <h3 class="font-semibold text-text-main text-sm truncate">网络接管</h3>
        </div>
        <button
          type="button"
          @click="emit('navigate', 'network')"
          class="app-btn-tonal app-btn-compact"
        >
          查看网络
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">系统网络状态</div>
          <div class="text-xs font-semibold truncate mt-0.5" :class="takeoverActive ? 'text-status-success' : 'text-text-muted'">
            {{ takeoverActive ? '已开启保护 (断网自动恢复)' : '未开启 (系统默认)' }}
          </div>
        </div>
        <div class="p-2.5 rounded-md bg-surface-card-sub border border-surface-border-sub">
          <div class="text-[11px] text-text-sub">防断网保障</div>
          <div class="text-[11px] font-mono text-text-sub truncate mt-0.5" title="%ProgramData%\DITING\dns_state.json">
            已就绪 (异常退出自动恢复)
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
