<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { CacheStats, CacheConfig, CacheEntryItem, CacheDomainStat, WebSocketEvent } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import MetricCard from '../components/MetricCard.vue';
import M3Icon from '../components/M3Icon.vue';

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
const searchQuery = ref('');
const statusFilter = ref<'all' | 'fresh' | 'stale' | 'negative'>('all');

const loading = ref(false);
const saving = ref(false);
const clearing = ref(false);
const errorMessage = ref('');
const successMessage = ref('');
const isClearDialogOpen = ref(false);

let pollTimer: any = null;
let unsubEvents: (() => void) | null = null;

const hitRatioPercent = computed(() => {
  const ratio = stats.value.hitRatio * 100;
  return `${ratio.toFixed(1)}%`;
});

const filteredEntries = computed(() => {
  return entries.value.filter((item) => {
    if (statusFilter.value === 'fresh' && item.status !== 'fresh') return false;
    if (statusFilter.value === 'stale' && item.status !== 'stale') return false;
    if (statusFilter.value === 'negative' && !item.isNegative) return false;
    return true;
  });
});

const maxTopHits = computed(() => {
  if (topDomains.value.length === 0) return 1;
  return Math.max(...topDomains.value.map((d) => d.hitCount), 1);
});

async function loadData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [st, cfg, entryRes, top] = await Promise.all([
      ipc.getCacheStats(),
      ipc.getCacheConfig(),
      ipc.getCacheEntries(searchQuery.value, 100),
      ipc.getCacheTopDomains(10),
    ]);
    stats.value = st;
    config.value = cfg;
    entries.value = entryRes.entries || [];
    totalEntriesCount.value = entryRes.total || 0;
    topDomains.value = top || [];
  } catch (err: any) {
    errorMessage.value = err.message || '加载缓存数据失败';
  } finally {
    loading.value = false;
  }
}

async function handleSearch() {
  try {
    const entryRes = await ipc.getCacheEntries(searchQuery.value, 100);
    entries.value = entryRes.entries || [];
    totalEntriesCount.value = entryRes.total || 0;
  } catch (err: any) {
    errorMessage.value = err.message;
  }
}

async function handleToggleCache(e: Event) {
  const target = e.target as any;
  const enable = Boolean(target.selected ?? target.checked);
  try {
    await ipc.updateCacheConfig({ enabled: enable });
    config.value.enabled = enable;
    stats.value.enabled = enable;
    successMessage.value = enable ? '智能缓存已启用' : '智能缓存已停用';
    setTimeout(() => (successMessage.value = ''), 3000);
  } catch (err: any) {
    errorMessage.value = `切换缓存失败: ${err.message}`;
    if ('selected' in target) {
      target.selected = !enable;
    } else {
      target.checked = !enable;
    }
  }
}

async function handleSaveConfig() {
  saving.value = true;
  errorMessage.value = '';
  successMessage.value = '';
  try {
    await ipc.updateCacheConfig(config.value);
    successMessage.value = '缓存策略配置已保存并即时生效！';
    await loadData();
    setTimeout(() => (successMessage.value = ''), 3000);
  } catch (err: any) {
    errorMessage.value = `保存配置失败: ${err.message}`;
  } finally {
    saving.value = false;
  }
}

async function handleConfirmClear() {
  clearing.value = true;
  try {
    await ipc.clearCache();
    isClearDialogOpen.value = false;
    successMessage.value = '智能缓存已全部清空！';
    await loadData();
    setTimeout(() => (successMessage.value = ''), 3000);
  } catch (err: any) {
    errorMessage.value = `清空缓存失败: ${err.message}`;
  } finally {
    clearing.value = false;
  }
}

function formatTime(timestampMs: number): string {
  if (!timestampMs || timestampMs <= 0) return '未命中';
  const d = new Date(timestampMs);
  return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;
}

onMounted(() => {
  loadData();
  pollTimer = setInterval(loadData, 4000);

  unsubEvents = ipc.onEvent((event: WebSocketEvent) => {
    if (event.type === 'query' || event.type === 'metrics') {
      // 收到请求事件时轻量同步
    }
  });
});

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
  if (unsubEvents) unsubEvents();
});
</script>

<template>
  <div class="space-y-6 pb-12">
    <!-- 头部操作与总控卡片 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <div class="flex items-center gap-2">
          <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
            智能 DNS 缓存大盘
          </h2>
          <StatusBadge
            :status="stats.enabled ? 'active' : 'inactive'"
            :text="stats.enabled ? '64 分片 LRU 运转中' : '缓存已停用'"
            size="sm"
          />
        </div>
        <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
          支持 64 分片高并发无锁竞争、RFC 2181/2308 动态 TTL 递减、Optimistic SWR 容灾与负缓存
        </p>
      </div>

      <div class="flex items-center gap-3">
        <!-- 缓存总控 Switch -->
        <div class="flex items-center gap-2 px-3 py-1.5 rounded-2xl bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 shadow-2xs">
          <span class="text-xs font-medium text-slate-600 dark:text-slate-300">智能缓存</span>
          <md-switch
            :selected="stats.enabled"
            @change="handleToggleCache"
          ></md-switch>
        </div>

        <!-- 刷新按钮 -->
        <md-outlined-button @click="loadData" :disabled="loading">
          <M3Icon slot="icon" name="refresh" :size="16" />
          刷新
        </md-outlined-button>

        <!-- 一键清空按钮 -->
        <md-filled-button
          class="m3-danger-btn"
          @click="isClearDialogOpen = true"
          :disabled="loading || stats.entryCount === 0"
        >
          <M3Icon slot="icon" name="delete" :size="16" />
          清空缓存
        </md-filled-button>
      </div>
    </div>

    <!-- 状态反馈提示 -->
    <div
      v-if="errorMessage"
      class="p-3 rounded-2xl bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900/60 text-xs text-rose-700 dark:text-rose-300 flex items-center justify-between shadow-2xs"
    >
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button @click="errorMessage = ''" class="hover:opacity-75">
        <M3Icon name="close" :size="16" />
      </button>
    </div>

    <div
      v-if="successMessage"
      class="p-3 rounded-2xl bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200 dark:border-emerald-900/60 text-xs text-emerald-700 dark:text-emerald-300 flex items-center gap-2 shadow-2xs"
    >
      <M3Icon name="check_circle" :size="18" />
      <span>{{ successMessage }}</span>
    </div>

    <!-- 核心指标遥测卡片网格 -->
    <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
      <!-- 缓存命中率高光卡片 -->
      <div class="p-4 rounded-3xl bg-primary/10 dark:bg-primary/15 border border-primary/20 flex flex-col justify-between">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-primary">缓存命中率</span>
          <M3Icon name="speed" :size="18" class="text-primary" />
        </div>
        <div class="my-2">
          <span class="text-2xl font-bold text-primary font-mono">{{ hitRatioPercent }}</span>
        </div>
        <!-- 简易环形/进度槽 -->
        <div class="w-full bg-slate-200/60 dark:bg-slate-700/60 rounded-full h-1.5 overflow-hidden">
          <div
            class="bg-primary h-full rounded-full transition-all duration-300"
            :style="{ width: `${Math.min(stats.hitRatio * 100, 100)}%` }"
          ></div>
        </div>
      </div>

      <MetricCard
        title="总命中数"
        :value="stats.totalHits.toLocaleString()"
        icon="check"
        subtext="缓存即时返回"
      />

      <MetricCard
        title="未命中回源"
        :value="stats.totalMisses.toLocaleString()"
        icon="sync"
        subtext="上游转发响应"
      />

      <MetricCard
        title="SWR 容灾命中"
        :value="stats.staleHits.toLocaleString()"
        icon="shield"
        subtext="陈旧条目保活"
      />

      <MetricCard
        title="负缓存拦截"
        :value="stats.negativeHits.toLocaleString()"
        icon="cancel"
        subtext="NXDOMAIN 拦截"
      />

      <MetricCard
        title="条目占用 / 容量"
        :value="`${stats.entryCount} / ${stats.maxEntries}`"
        icon="cache"
        :subtext="`淘汰数: ${stats.evictionCount}`"
      />
    </div>

    <!-- 双栏布局: 热点域名 Top 统计 & 缓存策略配置 -->
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
      <!-- 热点域名 Top 统计排行榜 (7 列) -->
      <div class="lg:col-span-7 p-6 rounded-3xl bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 shadow-2xs space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <M3Icon name="bolt" :size="20" class="text-amber-500" />
            <h3 class="text-base font-bold text-slate-900 dark:text-slate-100">热点域名 Top 统计</h3>
          </div>
          <span class="text-xs text-slate-400">实时请求频次排名前 10</span>
        </div>

        <div v-if="topDomains.length === 0" class="py-8 text-center text-xs text-slate-400">
          暂无缓存访问记录
        </div>

        <div v-else class="space-y-2.5">
          <div
            v-for="(item, idx) in topDomains"
            :key="item.domain + item.qtype"
            class="p-2.5 rounded-2xl bg-slate-50/70 dark:bg-slate-800/40 border border-slate-100 dark:border-slate-800 flex items-center justify-between gap-3 text-xs"
          >
            <!-- 排名与域名 -->
            <div class="flex items-center gap-3 min-w-0">
              <span
                class="w-5 h-5 rounded-full flex items-center justify-center font-bold font-mono text-[10px]"
                :class="idx < 3 ? 'bg-primary text-white' : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'"
              >
                {{ idx + 1 }}
              </span>
              <span class="font-mono font-medium text-slate-800 dark:text-slate-200 truncate" :title="item.domain">
                {{ item.domain }}
              </span>
              <span class="px-1.5 py-0.5 rounded text-[10px] font-mono bg-slate-200/60 dark:bg-slate-700/60 text-slate-600 dark:text-slate-300">
                {{ item.qtype }}
              </span>
            </div>

            <!-- 频次柱状进度与命中数 -->
            <div class="flex items-center gap-3 shrink-0">
              <div class="w-20 md:w-28 bg-slate-200 dark:bg-slate-700 rounded-full h-1.5 overflow-hidden hidden sm:block">
                <div
                  class="bg-amber-500 h-full rounded-full"
                  :style="{ width: `${(item.hitCount / maxTopHits) * 100}%` }"
                ></div>
              </div>
              <span class="font-mono font-bold text-slate-700 dark:text-slate-300 min-w-8 text-right">
                {{ item.hitCount }} 次
              </span>
              <span class="text-[10px] text-slate-400 min-w-14 text-right">
                {{ formatTime(item.lastHitAt) }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- 缓存运行策略配置 (5 列) -->
      <div class="lg:col-span-5 p-6 rounded-3xl bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 shadow-2xs space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <M3Icon name="settings" :size="20" class="text-primary" />
            <h3 class="text-base font-bold text-slate-900 dark:text-slate-100">缓存策略参数</h3>
          </div>
          <md-filled-button @click="handleSaveConfig" :disabled="saving">
            保存配置
          </md-filled-button>
        </div>

        <div class="space-y-4 pt-1">
          <!-- TTL 策略模式 -->
          <div class="space-y-1">
            <label class="text-xs font-medium text-slate-700 dark:text-slate-300">TTL 计算模式</label>
            <md-outlined-select
              :value="config.mode"
              @change="config.mode = ($event.target as any).value"
              class="w-full"
            >
              <md-select-option value="limit_max_ttl">
                <div slot="headline">限制最大 TTL (推荐)</div>
              </md-select-option>
              <md-select-option value="follow_dns_ttl">
                <div slot="headline">完全跟随上游 DNS TTL</div>
              </md-select-option>
              <md-select-option value="fixed_ttl">
                <div slot="headline">固定 TTL 模式</div>
              </md-select-option>
            </md-outlined-select>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <md-outlined-text-field
              label="最大 TTL (秒)"
              type="number"
              :value="String(config.maxTtlSeconds)"
              @input="config.maxTtlSeconds = Number(($event.target as any).value)"
            ></md-outlined-text-field>

            <md-outlined-text-field
              label="最小保证 TTL (秒)"
              type="number"
              :value="String(config.minTtlSeconds)"
              @input="config.minTtlSeconds = Number(($event.target as any).value)"
            ></md-outlined-text-field>
          </div>

          <!-- Stale 容灾与 Optimistic SWR 开关 -->
          <div class="p-3 rounded-2xl bg-slate-50 dark:bg-slate-800/60 border border-slate-100 dark:border-slate-800 space-y-3">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-xs font-bold text-slate-800 dark:text-slate-200">Stale 容灾保活 (SWR)</span>
                <p class="text-[11px] text-slate-500">上游异常或过期宽限期内提供快速容灾响应</p>
              </div>
              <md-switch
                :selected="config.staleFallbackEnabled"
                @change="config.staleFallbackEnabled = Boolean(($event.target as any).selected ?? ($event.target as any).checked)"
              ></md-switch>
            </div>

            <div v-if="config.staleFallbackEnabled" class="grid grid-cols-2 gap-3 pt-1">
              <md-outlined-text-field
                label="保活宽限时长 (秒)"
                type="number"
                :value="String(config.staleFallbackSeconds)"
                @input="config.staleFallbackSeconds = Number(($event.target as any).value)"
              ></md-outlined-text-field>

              <div class="flex items-center justify-between px-2">
                <span class="text-[11px] text-slate-600 dark:text-slate-400">Optimistic 优先响应</span>
                <md-switch
                  :selected="config.optimistic"
                  @change="config.optimistic = Boolean(($event.target as any).selected ?? ($event.target as any).checked)"
                ></md-switch>
              </div>
            </div>
          </div>

          <!-- 负缓存配置 -->
          <div class="p-3 rounded-2xl bg-slate-50 dark:bg-slate-800/60 border border-slate-100 dark:border-slate-800 flex items-center justify-between">
            <div>
              <span class="text-xs font-bold text-slate-800 dark:text-slate-200">负缓存 (Negative Caching)</span>
              <p class="text-[11px] text-slate-500">缓存 NXDOMAIN 与 NODATA 减少重复无效回源</p>
            </div>
            <md-switch
              :selected="config.negativeTtlEnabled"
              @change="config.negativeTtlEnabled = Boolean(($event.target as any).selected ?? ($event.target as any).checked)"
            ></md-switch>
          </div>
        </div>
      </div>
    </div>

    <!-- 缓存条目检索与表格 -->
    <div class="p-6 rounded-3xl bg-white dark:bg-slate-900 border border-slate-200/80 dark:border-slate-800 shadow-2xs space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div class="flex items-center gap-2">
          <M3Icon name="search" :size="20" class="text-primary" />
          <h3 class="text-base font-bold text-slate-900 dark:text-slate-100">
            缓存条目检索 ({{ totalEntriesCount }} 条)
          </h3>
        </div>

        <div class="flex items-center gap-3">
          <!-- 搜索输入框 -->
          <md-outlined-text-field
            placeholder="搜索域名或记录类型..."
            :value="searchQuery"
            @input="searchQuery = ($event.target as any).value"
            @keyup.enter="handleSearch"
            class="w-60 font-mono text-xs"
          >
            <M3Icon slot="leading-icon" name="search" :size="16" />
          </md-outlined-text-field>

          <md-outlined-button @click="handleSearch">
            检索
          </md-outlined-button>
        </div>
      </div>

      <!-- 状态过滤 Chips -->
      <div class="flex items-center gap-2">
        <button
          v-for="f in [
            { id: 'all', label: '全部' },
            { id: 'fresh', label: '生效中 (Fresh)' },
            { id: 'stale', label: '容灾保活 (Stale)' },
            { id: 'negative', label: '负缓存 (Negative)' },
          ]"
          :key="f.id"
          @click="statusFilter = f.id as any"
          class="px-3 py-1 rounded-full text-xs font-medium transition-colors"
          :class="statusFilter === f.id ? 'bg-primary text-white' : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 hover:bg-slate-200'"
        >
          {{ f.label }}
        </button>
      </div>

      <!-- 条目列表 -->
      <div v-if="filteredEntries.length === 0" class="py-12 text-center text-xs text-slate-400">
        未匹配到符合条件的缓存条目
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full text-left text-xs font-mono">
          <thead>
            <tr class="border-b border-slate-200 dark:border-slate-800 text-slate-400">
              <th class="py-2.5 font-medium">域名 (Domain)</th>
              <th class="py-2.5 font-medium">类型</th>
              <th class="py-2.5 font-medium">状态</th>
              <th class="py-2.5 font-medium">剩余 TTL</th>
              <th class="py-2.5 font-medium">初始 TTL</th>
              <th class="py-2.5 font-medium">命中数</th>
              <th class="py-2.5 font-medium">解析地址</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-slate-800/60">
            <tr
              v-for="entry in filteredEntries"
              :key="entry.domain + entry.qtype"
              class="hover:bg-slate-50/60 dark:hover:bg-slate-800/40 transition-colors"
            >
              <td class="py-2.5 font-bold text-slate-800 dark:text-slate-200">
                {{ entry.domain }}
              </td>
              <td class="py-2.5 text-slate-600 dark:text-slate-400">
                {{ entry.qtype }}
              </td>
              <td class="py-2.5">
                <span
                  v-if="entry.isNegative"
                  class="px-2 py-0.5 rounded-full text-[10px] bg-rose-100 dark:bg-rose-950/60 text-rose-700 dark:text-rose-300"
                >
                  负缓存
                </span>
                <span
                  v-else-if="entry.status === 'fresh'"
                  class="px-2 py-0.5 rounded-full text-[10px] bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-300"
                >
                  生效中
                </span>
                <span
                  v-else
                  class="px-2 py-0.5 rounded-full text-[10px] bg-amber-100 dark:bg-amber-950/60 text-amber-700 dark:text-amber-300"
                >
                  容灾保活
                </span>
              </td>
              <td class="py-2.5 font-bold" :class="entry.remainingTtl > 0 ? 'text-primary' : 'text-amber-500'">
                {{ entry.remainingTtl }}s
              </td>
              <td class="py-2.5 text-slate-400">
                {{ entry.originalTtl }}s
              </td>
              <td class="py-2.5 text-slate-700 dark:text-slate-300 font-bold">
                {{ entry.hitCount }}
              </td>
              <td class="py-2.5 text-slate-500 max-w-xs truncate" :title="entry.ipList?.join(', ') || '无'">
                {{ entry.ipList && entry.ipList.length > 0 ? entry.ipList.join(', ') : '-' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 一键清空确认弹窗 (标准 M3 Dialog) -->
    <md-dialog :open="isClearDialogOpen" @close="isClearDialogOpen = false" type="alert">
      <div slot="headline" class="flex items-center gap-2 text-rose-600 dark:text-rose-400">
        <M3Icon name="delete" :size="22" />
        <span>清空所有智能缓存？</span>
      </div>
      <form slot="content" id="clear-dialog-form" method="dialog" class="space-y-2 pt-1">
        <p class="text-xs text-slate-600 dark:text-slate-400 leading-relaxed">
          此操作将清空当前 64 分片内的全部活跃条目（共 {{ stats.entryCount }} 条）与 LRU 热度队列。后续 DNS 请求将重新回源解析并重新填充缓存。
        </p>
      </form>
      <div slot="actions">
        <md-text-button form="clear-dialog-form" value="cancel" @click="isClearDialogOpen = false">取消</md-text-button>
        <md-filled-button
          form="clear-dialog-form"
          value="confirm"
          class="m3-danger-btn"
          :disabled="clearing"
          @click="handleConfirmClear"
        >
          确认清空
        </md-filled-button>
      </div>
    </md-dialog>
  </div>
</template>
