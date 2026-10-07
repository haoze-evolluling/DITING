<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { StatusResponse, WebSocketEvent } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import MetricCard from '../components/MetricCard.vue';
import MetricChart from '../components/MetricChart.vue';
import M3Icon from '../components/M3Icon.vue';

const emit = defineEmits<{
  (e: 'navigate', tab: string): void;
}>();

const status = ref<StatusResponse | null>(null);
const loading = ref(false);
const togglingDNS = ref(false);
const togglingTakeover = ref(false);
const errorMessage = ref('');

const qpsHistory = ref<number[]>([]);
const latencyHistory = ref<number[]>([]);

let unsubEvents: (() => void) | null = null;
let unsubConn: (() => void) | null = null;
let pollTimer: any = null;

const dnsRunning = computed(() => !!status.value?.dns?.running);
const takeoverActive = computed(() => !!status.value?.takeover?.active);
const activeAdaptersCount = computed(() => status.value?.takeover?.adapters?.length || 0);

const successRate = computed(() => {
  const m = status.value?.metrics;
  if (!m || m.totalQueries === 0) return '100.0%';
  const rate = (m.successQueries / m.totalQueries) * 100;
  return `${rate.toFixed(1)}%`;
});

const formatUptime = computed(() => {
  const sec = status.value?.uptimeSeconds || 0;
  const hours = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (hours > 0) return `${hours}小时 ${mins}分`;
  if (mins > 0) return `${mins}分 ${s}秒`;
  return `${s}秒`;
});

async function fetchStatus() {
  try {
    loading.value = true;
    errorMessage.value = '';
    const res = await ipc.getStatus();
    status.value = res;
    if (res.metrics) {
      pushMetricData(res.metrics.qps, res.metrics.avgLatencyMs);
    }
  } catch (err: any) {
    errorMessage.value = err.message || '获取服务状态失败';
  } finally {
    loading.value = false;
  }
}

function pushMetricData(qps: number, latency: number) {
  qpsHistory.value = [...qpsHistory.value.slice(-29), qps];
  latencyHistory.value = [...latencyHistory.value.slice(-29), latency];
}

async function handleToggleDNS(e: Event) {
  const target = e.target as any;
  const wantStart = target.selected ?? !dnsRunning.value;
  try {
    togglingDNS.value = true;
    errorMessage.value = '';
    if (wantStart) {
      await ipc.startDNS();
    } else {
      await ipc.stopDNS();
    }
    await fetchStatus();
  } catch (err: any) {
    errorMessage.value = `DNS 操作失败: ${err.message}`;
    target.selected = dnsRunning.value;
  } finally {
    togglingDNS.value = false;
  }
}

async function handleToggleTakeover(e: Event) {
  const target = e.target as any;
  const nextVal = Boolean(target.selected ?? target.checked);
  togglingTakeover.value = true;
  try {
    if (nextVal) {
      await ipc.enableTakeover();
    } else {
      await ipc.disableTakeover();
    }
    await fetchStatus();
  } catch (err: any) {
    errorMessage.value = `网卡接管操作失败: ${err.message}`;
    if ('selected' in target) {
      target.selected = !nextVal;
    } else {
      target.checked = !nextVal;
    }
  } finally {
    togglingTakeover.value = false;
  }
}

onMounted(() => {
  fetchStatus();

  unsubEvents = ipc.onEvent((event: WebSocketEvent) => {
    if (event.type === 'metrics') {
      const m = event.data;
      if (status.value) {
        status.value.metrics = m;
      }
      pushMetricData(m.qps || 0, m.avgLatencyMs || 0);
    } else if (event.type === 'dns' || event.type === 'takeover' || event.type === 'upstream') {
      fetchStatus();
    }
  });

  unsubConn = ipc.onConnectionChange((connected) => {
    if (connected) {
      fetchStatus();
    }
  });

  pollTimer = setInterval(fetchStatus, 5000);
});

onUnmounted(() => {
  if (unsubEvents) unsubEvents();
  if (unsubConn) unsubConn();
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="space-y-6 pb-12 select-none">
    <!-- 顶部状态提示条 -->
    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-status-error-bg border border-status-error/20 px-4 py-2.5 text-sm text-status-error">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button
        @click="fetchStatus"
        class="app-btn-secondary app-btn-compact"
      >
        <M3Icon name="refresh" :size="14" />
        <span>重试</span>
      </button>
    </div>

    <!-- 16:9 双栏全景主网格 (左侧：核心控制 + 指标 + 波形图表；右侧：快捷模块摘要) -->
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-5 items-start">
      <!-- 左侧主控与实时监控栏 (占据 8/12 宽度) -->
      <div class="xl:col-span-8 flex flex-col gap-4">
        <!-- 核心状态总控卡片 (紧凑现代) -->
        <div class="relative overflow-hidden rounded-3xl border border-surface-border bg-surface-card p-5 sm:p-6 shadow-xs transition-colors">
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-5">
            <div class="space-y-1.5 min-w-0">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h2 class="text-xl sm:text-2xl font-bold tracking-tight text-text-main">
                  系统 DNS 转发核心
                </h2>
                <StatusBadge
                  :status="dnsRunning ? 'active' : 'inactive'"
                  :text="dnsRunning ? '监听运行中' : '服务已暂停'"
                  :pulse="dnsRunning"
                />
                <StatusBadge
                  v-if="takeoverActive"
                  status="active"
                  :text="`已接管 ${activeAdaptersCount} 个物理网卡`"
                  size="sm"
                />
              </div>
              <p class="text-xs sm:text-sm text-text-sub max-w-xl line-clamp-2">
                谛听 (DITING) 双栈 DNS 内核正在 Windows 平台运行，提供毫秒级多协议上游调度、安全故障回退与崩溃状态持久化自愈。
              </p>
            </div>

            <!-- 主控制开关组 -->
            <div class="flex items-center gap-4 bg-surface-card-sub px-4 py-3 rounded-2xl border border-surface-border-sub shrink-0">
              <!-- DNS 代理服务开关 -->
              <div class="flex items-center gap-2.5">
                <div class="flex flex-col text-right">
                  <span class="text-xs sm:text-sm font-semibold text-text-main">DNS 监听</span>
                  <span class="text-[11px] text-text-muted">127.0.0.1:53</span>
                </div>
                <md-switch
                  :selected="dnsRunning"
                  :disabled="togglingDNS"
                  @change="handleToggleDNS"
                />
              </div>

              <div class="h-6 w-px bg-surface-border" />

              <!-- 网卡接管开关 -->
              <div class="flex items-center gap-2.5">
                <div class="flex flex-col text-right">
                  <span class="text-xs sm:text-sm font-semibold text-text-main">网卡接管</span>
                  <span class="text-[11px] text-text-muted">双栈回路</span>
                </div>
                <md-switch
                  :selected="takeoverActive"
                  :disabled="togglingTakeover || !dnsRunning"
                  @change="handleToggleTakeover"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- 实时遥测高光指标卡片 (4 列排布，在 8/12 宽度下非常宽敞) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3.5">
          <MetricCard
            title="实时查询 QPS"
            :value="(status?.metrics?.qps || 0).toFixed(1)"
            unit="req/s"
            icon="speed"
            subtext="当前请求吞吐率"
          />
          <MetricCard
            title="平均响应延迟"
            :value="(status?.metrics?.avgLatencyMs || 0).toFixed(1)"
            unit="ms"
            icon="bolt"
            subtext="上游综合 RTT"
          />
          <MetricCard
            title="查询成功率"
            :value="successRate"
            icon="check_circle"
            :subtext="`成功: ${status?.metrics?.successQueries || 0} / 失败: ${status?.metrics?.failedQueries || 0}`"
          />
          <MetricCard
            title="核心运行时间"
            :value="formatUptime"
            icon="shield"
            :subtext="`进程 PID: ${status?.pid || '-'}`"
          />
        </div>

        <!-- 遥测波形图表 (双图表并列) -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <MetricChart
            label="QPS 实时波形曲线 (req/s)"
            :data="qpsHistory"
            strokeColor="var(--app-brand-primary)"
            gradientId="chart-grad-qps"
            unit="req/s"
            :height="115"
          />
          <MetricChart
            label="延迟波动历史 (ms)"
            :data="latencyHistory"
            strokeColor="var(--app-status-warning)"
            gradientId="chart-grad-latency"
            unit="ms"
            :height="115"
          />
        </div>
      </div>

      <!-- 右侧快捷功能与监控摘要栏 (占据 4/12 宽度) -->
      <div class="xl:col-span-4 flex flex-col gap-3.5">
        <!-- 上游节点摘要 -->
        <div class="rounded-2xl border border-surface-border bg-surface-card p-4 shadow-xs transition-colors">
          <div class="flex items-center justify-between gap-2 mb-2.5">
            <div class="flex items-center gap-2 min-w-0">
              <M3Icon name="upstream" :size="18" class="text-brand-primary shrink-0" />
              <h3 class="font-semibold text-text-main text-sm truncate">上游调度</h3>
            </div>
            <button
              @click="emit('navigate', 'upstream')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              管理配置
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">调度策略</div>
              <div class="text-xs font-semibold text-text-main uppercase truncate mt-0.5">
                {{ status?.dns?.mode || 'PRIMARY_BACKUP' }}
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">活动节点</div>
              <div class="text-xs font-semibold text-text-main truncate mt-0.5">
                {{ status?.dns?.upstreams?.length || 0 }} 个节点
              </div>
            </div>
          </div>
        </div>

        <!-- 智能缓存摘要 -->
        <div class="rounded-2xl border border-surface-border bg-surface-card p-4 shadow-xs transition-colors">
          <div class="flex items-center justify-between gap-2 mb-2.5">
            <div class="flex items-center gap-2 min-w-0">
              <M3Icon name="cache" :size="18" class="text-brand-primary shrink-0" />
              <h3 class="font-semibold text-text-main text-sm truncate">智能缓存</h3>
            </div>
            <button
              @click="emit('navigate', 'cache')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              缓存监控
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">实时命中率</div>
              <div class="text-xs font-bold text-brand-primary font-mono mt-0.5">
                {{ ((status?.cache?.hitRatio || 0) * 100).toFixed(1) }}%
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">条目数 / 容量</div>
              <div class="text-xs font-mono text-text-main truncate mt-0.5">
                {{ status?.cache?.entryCount || 0 }} / {{ status?.cache?.maxEntries || 4096 }}
              </div>
            </div>
          </div>
        </div>

        <!-- 规则防护摘要 -->
        <div class="rounded-2xl border border-surface-border bg-surface-card p-4 shadow-xs transition-colors">
          <div class="flex items-center justify-between gap-2 mb-2.5">
            <div class="flex items-center gap-2 min-w-0">
              <M3Icon name="shield" :size="18" class="text-brand-primary shrink-0" />
              <h3 class="font-semibold text-text-main text-sm truncate">规则拦截</h3>
            </div>
            <button
              @click="emit('navigate', 'rules')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              管理规则
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">请求拦截率</div>
              <div class="text-xs font-bold text-status-error font-mono mt-0.5">
                {{ (status?.filter?.blockRate || 0).toFixed(1) }}%
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">拦截 / 总规则</div>
              <div class="text-xs font-mono text-text-main truncate mt-0.5">
                {{ status?.filter?.blockedQueries || 0 }} / {{ status?.filter?.totalRules || 0 }}
              </div>
            </div>
          </div>
        </div>

        <!-- 网卡接管简报 -->
        <div class="rounded-2xl border border-surface-border bg-surface-card p-4 shadow-xs transition-colors">
          <div class="flex items-center justify-between gap-2 mb-2.5">
            <div class="flex items-center gap-2 min-w-0">
              <M3Icon name="adapters" :size="18" class="text-brand-primary shrink-0" />
              <h3 class="font-semibold text-text-main text-sm truncate">网卡接管</h3>
            </div>
            <button
              @click="emit('navigate', 'adapters')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              查看详情
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">系统接管状态</div>
              <div class="text-xs font-semibold truncate mt-0.5" :class="takeoverActive ? 'text-status-success' : 'text-text-muted'">
                {{ takeoverActive ? '已接管 (自动灾备)' : '未接管 (系统原生)' }}
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">持久化状态</div>
              <div class="text-[11px] font-mono text-text-sub truncate mt-0.5" title="%ProgramData%\DITING\dns_state.json">
                已持久化自愈
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
