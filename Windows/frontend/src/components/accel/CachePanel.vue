<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { ipc } from '../../api/ipc';
import type { CacheStats, CacheConfig, CacheEntryItem, CacheDomainStat } from '../../api/types';
import StatusBadge from '../StatusBadge.vue';
import Panel from '../ui/Panel.vue';
import M3Icon from '../M3Icon.vue';
import AppModal from '../AppModal.vue';
import ToastBanner from '../ToastBanner.vue';
import CacheTopDomains from './CacheTopDomains.vue';
import CacheConfigCard from './CacheConfigCard.vue';
import CacheEntriesTable from './CacheEntriesTable.vue';
import { revertSwitch, extractSwitchValue } from '../../utils/switch';
import { usePoller } from '../../composables/usePoller';
import { useToast } from '../../composables/useToast';

const stats = ref<CacheStats>({
  enabled: true,
  totalHits: 0,
  totalMisses: 0,
  staleHits: 0,
  negativeHits: 0,
  hitRatio: 0,
  entryCount: 0,
  maxEntries: 4096,
  evictionCount: 0,
});

const config = ref<CacheConfig>({
  enabled: true,
  maxEntries: 4096,
  mode: 'limit_max_ttl',
  maxTtlSeconds: 3600,
  fixedTtlSeconds: 3600,
  minTtlEnabled: true,
  minTtlSeconds: 60,
  staleFallbackEnabled: true,
  staleFallbackSeconds: 300,
  negativeTtlEnabled: true,
  negativeTtlSeconds: 30,
  optimistic: true,
});

const entries = ref<CacheEntryItem[]>([]);
const topDomains = ref<CacheDomainStat[]>([]);
const totalEntriesCount = ref(0);
const currentSearch = ref('');

const loading = ref(false);
const saving = ref(false);
const clearing = ref(false);
const isClearDialogOpen = ref(false);
const { toast, show: showToast, dismiss } = useToast();

const hitRatioPercent = computed(() => {
  const ratio = (stats.value.hitRatio || 0) * 100;
  return `${ratio.toFixed(1)}%`;
});

const cacheStats = computed(() => [
  { label: '总命中数', value: stats.value.totalHits.toLocaleString() },
  { label: '实时联网解析', value: stats.value.totalMisses.toLocaleString() },
  { label: '弱网应急保障', value: stats.value.staleHits.toLocaleString() },
  { label: '无效网址拦截', value: stats.value.negativeHits.toLocaleString() },
  { label: '已存记录 / 上限', value: `${stats.value.entryCount} / ${stats.value.maxEntries}` },
]);

async function loadData() {
  loading.value = true;
  try {
    const [st, cfg, entryRes, top] = await Promise.all([
      ipc.getCacheStats(),
      ipc.getCacheConfig(),
      ipc.getCacheEntries(currentSearch.value, 100),
      ipc.getCacheTopDomains(10),
    ]);
    stats.value = st;
    config.value = cfg;
    entries.value = entryRes?.entries || [];
    totalEntriesCount.value = entryRes?.total || 0;
    topDomains.value = top || [];
  } catch (err: any) {
    showToast(err.message || '加载缓存数据失败', true);
  } finally {
    loading.value = false;
  }
}

async function pollMetrics() {
  try {
    const [st, entryRes, top] = await Promise.all([
      ipc.getCacheStats(),
      ipc.getCacheEntries(currentSearch.value, 100),
      ipc.getCacheTopDomains(10),
    ]);
    stats.value = st;
    entries.value = entryRes?.entries || [];
    totalEntriesCount.value = entryRes?.total || 0;
    topDomains.value = top || [];
  } catch {
    // 忽略静默遥测异常
  }
}

async function handleSearch(query: string) {
  currentSearch.value = query;
  try {
    const entryRes = await ipc.getCacheEntries(query, 100);
    entries.value = entryRes?.entries || [];
    totalEntriesCount.value = entryRes?.total || 0;
  } catch (err: any) {
    showToast(err.message, true);
  }
}

async function handleToggleCache(e: Event) {
  const enable = extractSwitchValue(e);
  try {
    const updated = { ...config.value, enabled: enable };
    await ipc.updateCacheConfig(updated);
    config.value = updated;
    stats.value.enabled = enable;
    showToast(enable ? '解析加速已开启' : '解析加速已关闭');
  } catch (err: any) {
    showToast(`切换加速状态失败: ${err.message}`, true);
    revertSwitch(e, !enable);
  }
}

async function handleSaveConfig() {
  saving.value = true;
  try {
    await ipc.updateCacheConfig(config.value);
    showToast('加速策略配置已保存并即时生效！');
    await loadData();
  } catch (err: any) {
    showToast(`保存配置失败: ${err.message}`, true);
  } finally {
    saving.value = false;
  }
}

async function handleConfirmClear() {
  clearing.value = true;
  try {
    await ipc.clearCache();
    isClearDialogOpen.value = false;
    showToast('加速缓存已全部清空！');
    await loadData();
  } catch (err: any) {
    showToast(`清空缓存失败: ${err.message}`, true);
  } finally {
    clearing.value = false;
  }
}

onMounted(() => {
  loadData();
});

usePoller(pollMetrics, 4000);
</script>

<template>
  <div class="space-y-5 pb-12 select-none">
    <!-- 头部操作与总控栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <div class="flex items-center gap-2.5">
          <h2 class="section-title">智能解析加速中心</h2>
          <StatusBadge
            :status="stats.enabled ? 'active' : 'inactive'"
            :text="stats.enabled ? '加速引擎运行中' : '加速已停用'"
            size="sm"
          />
        </div>
        <p class="text-xs text-text-sub mt-1">
          自动缓存已访问过的网址解析结果，下次访问直接瞬间返回；在断网或网络卡顿时自动启用应急保障。
        </p>
      </div>

      <div class="flex items-center gap-3">
        <!-- 缓存总控 Switch（容器 34px 与相邻按钮等高） -->
        <div class="flex items-center gap-2 h-[34px] px-3 rounded-md bg-surface-card border border-surface-border">
          <span class="text-xs font-medium text-text-sub">解析加速</span>
          <md-switch
            :selected="stats.enabled"
            @change="handleToggleCache"
          ></md-switch>
        </div>

        <!-- 刷新按钮 -->
        <button
          type="button"
          @click="loadData"
          :disabled="loading"
          class="app-btn-secondary"
        >
          <M3Icon name="refresh" :size="16" :class="loading ? 'animate-spin' : ''" />
          <span>刷新</span>
        </button>

        <!-- 一键清空按钮 -->
        <button
          type="button"
          @click="isClearDialogOpen = true"
          :disabled="loading || stats.entryCount === 0"
          class="app-btn-danger"
        >
          <M3Icon name="delete" :size="16" />
          <span>清空缓存</span>
        </button>
      </div>
    </div>

    <!-- 状态反馈提示 -->
    <ToastBanner
      v-if="toast"
      :message="toast.message"
      :type="toast.isError ? 'error' : 'success'"
      compact
      dismissible
      @dismiss="dismiss"
    />

    <!-- 命中率（唯一强调数字）+ 指标带 -->
    <Panel>
      <div class="flex items-baseline gap-3 mb-3">
        <span class="label-quiet">缓存命中率</span>
        <span class="font-mono text-[32px] font-semibold leading-none text-text-main tabular-nums">
          {{ hitRatioPercent }}
        </span>
      </div>
      <div class="w-full bg-surface-card-sub rounded-full h-1.5 overflow-hidden">
        <div
          class="bg-accent-seal h-full rounded-full transition-all duration-300"
          :style="{ width: `${Math.min((stats.hitRatio || 0) * 100, 100)}%` }"
        />
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-x-6 gap-y-4 mt-5 pt-4 border-t border-surface-border-sub">
        <div v-for="s in cacheStats" :key="s.label">
          <div class="label-quiet">{{ s.label }}</div>
          <div class="mt-0.5 font-mono text-[17px] font-semibold text-text-main tabular-nums">
            {{ s.value }}
          </div>
        </div>
      </div>
    </Panel>

    <!-- 双栏等宽布局: 热点域名 Top 统计 & 缓存策略配置 -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <CacheTopDomains :topDomains="topDomains" />
      <CacheConfigCard :config="config" :saving="saving" @save="handleSaveConfig" />
    </div>

    <!-- 缓存条目检索与表格 -->
    <CacheEntriesTable
      :entries="entries"
      :totalCount="totalEntriesCount"
      @search="handleSearch"
    />

    <!-- 一键清空确认弹窗 -->
    <AppModal
      :open="isClearDialogOpen"
      @close="isClearDialogOpen = false"
      type="alert"
    >
      <template #headline>
        <div class="flex items-center gap-2 text-status-error font-bold">
          <M3Icon name="delete" :size="22" />
          <span>确定清空所有加速缓存？</span>
        </div>
      </template>

      <div class="space-y-2 pt-1 text-xs text-text-sub leading-relaxed">
        <p>
          此操作将清空当前全部已缓存的网址记录（共 {{ stats.entryCount }} 条）。清空后后续访问网址将重新通过网络解析。
        </p>
      </div>

      <template #actions>
        <button
          type="button"
          @click="isClearDialogOpen = false"
          class="app-btn-secondary"
        >
          取消
        </button>
        <button
          type="button"
          :disabled="clearing"
          @click="handleConfirmClear"
          class="app-btn-danger"
        >
          确认清空
        </button>
      </template>
    </AppModal>
  </div>
</template>
