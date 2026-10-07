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
    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-status-error-bg border border-status-error/20 px-4 py-3 text-sm text-status-error">
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

    <!-- 核心状态总控大卡片 -->
    <div class="relative overflow-hidden rounded-3xl border border-surface-border bg-surface-card p-7 shadow-xs transition-colors">
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div class="space-y-2">
          <div class="flex items-center gap-3">
            <h2 class="text-2xl font-bold tracking-tight text-text-main">
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
          <p class="text-sm text-text-sub max-w-xl">
            谛听 (DITING) 双栈 DNS 内核正在 Windows 平台运行，提供毫秒级多协议上游调度、安全故障回退与崩溃状态持久化自愈。
          </p>
        </div>

        <!-- 主控制开关组 -->
        <div class="flex flex-wrap items-center gap-6 bg-surface-card-sub p-4 rounded-2xl border border-surface-border-sub">
          <!-- DNS 代理服务开关 -->
          <div class="flex items-center gap-3">
            <div class="flex flex-col text-right">
              <span class="text-sm font-semibold text-text-main">DNS 代理监听</span>
              <span class="text-xs text-text-muted">127.0.0.1:53</span>
            </div>
            <md-switch
              :selected="dnsRunning"
              :disabled="togglingDNS"
              @change="handleToggleDNS"
            />
          </div>

          <div class="h-8 w-px bg-surface-border" />

          <!-- 网卡接管开关 -->
          <div class="flex items-center gap-3">
            <div class="flex flex-col text-right">
              <span class="text-sm font-semibold text-text-main">物理网卡接管</span>
              <span class="text-xs text-text-muted">双栈 127.0.0.1 / ::1</span>
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

    <!-- 实时遥测高光指标卡片 -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
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

    <!-- 遥测波形图表 -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <MetricChart
        label="QPS 实时波形曲线 (req/s)"
        :data="qpsHistory"
        strokeColor="var(--app-brand-primary)"
        gradientId="chart-grad-qps"
        unit="req/s"
      />
      <MetricChart
        label="延迟波动历史 (ms)"
        :data="latencyHistory"
        strokeColor="var(--app-status-warning)"
        gradientId="chart-grad-latency"
        unit="ms"
      />
    </div>

    <!-- 快捷摘要四列面板 (上游、缓存、规则防护、网卡) -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
      <!-- 上游节点摘要 -->
      <div class="rounded-2xl border border-surface-border bg-surface-card p-5 shadow-xs transition-colors">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="upstream" :size="18" class="text-brand-primary" />
            <h3 class="font-semibold text-text-main">当前上游调度模式</h3>
          </div>
          <button
            @click="emit('navigate', 'upstream')"
            class="h-7 px-3 rounded-lg text-xs font-semibold text-brand-primary bg-brand-container/50 hover:bg-brand-container transition-colors cursor-pointer inline-flex items-center"
          >
            管理配置
          </button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">调度策略</span>
            <span class="text-sm font-semibold text-text-main uppercase">
              {{ status?.dns?.mode || 'PRIMARY_BACKUP' }}
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">活动节点数</span>
            <span class="text-sm font-semibold text-text-main">
              {{ status?.dns?.upstreams?.length || 0 }} 个上游节点
            </span>
          </div>
        </div>
      </div>

      <!-- 智能缓存摘要 -->
      <div class="rounded-2xl border border-surface-border bg-surface-card p-5 shadow-xs transition-colors">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="cache" :size="18" class="text-brand-primary" />
            <h3 class="font-semibold text-text-main">智能缓存大盘</h3>
          </div>
          <button
            @click="emit('navigate', 'cache')"
            class="h-7 px-3 rounded-lg text-xs font-semibold text-brand-primary bg-brand-container/50 hover:bg-brand-container transition-colors cursor-pointer inline-flex items-center"
          >
            缓存监控
          </button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">实时命中率</span>
            <span class="text-sm font-bold text-brand-primary font-mono">
              {{ ((status?.cache?.hitRatio || 0) * 100).toFixed(1) }}%
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">条目数 / 容量</span>
            <span class="text-xs font-mono text-text-main">
              {{ status?.cache?.entryCount || 0 }} / {{ status?.cache?.maxEntries || 4096 }}
            </span>
          </div>
        </div>
      </div>

      <!-- 规则防护摘要 -->
      <div class="rounded-2xl border border-surface-border bg-surface-card p-5 shadow-xs transition-colors">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="shield" :size="18" class="text-brand-primary" />
            <h3 class="font-semibold text-text-main">规则拦截大盘</h3>
          </div>
          <button
            @click="emit('navigate', 'rules')"
            class="h-7 px-3 rounded-lg text-xs font-semibold text-brand-primary bg-brand-container/50 hover:bg-brand-container transition-colors cursor-pointer inline-flex items-center"
          >
            管理规则
          </button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">请求拦截率</span>
            <span class="text-sm font-bold text-status-error font-mono">
              {{ (status?.filter?.blockRate || 0).toFixed(1) }}%
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">拦截数 / 规则</span>
            <span class="text-xs font-mono text-text-main">
              {{ status?.filter?.blockedQueries || 0 }} 拦截 / {{ status?.filter?.totalRules || 0 }} 规则
            </span>
          </div>
        </div>
      </div>

      <!-- 网卡接管简报 -->
      <div class="rounded-2xl border border-surface-border bg-surface-card p-5 shadow-xs transition-colors">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="adapters" :size="18" class="text-brand-primary" />
            <h3 class="font-semibold text-text-main">物理网卡接管简报</h3>
          </div>
          <button
            @click="emit('navigate', 'adapters')"
            class="h-7 px-3 rounded-lg text-xs font-semibold text-brand-primary bg-brand-container/50 hover:bg-brand-container transition-colors cursor-pointer inline-flex items-center"
          >
            查看详情
          </button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">系统接管状态</span>
            <span class="text-sm font-semibold" :class="takeoverActive ? 'text-status-success' : 'text-text-muted'">
              {{ takeoverActive ? '已接管 (自动灾备)' : '未接管 (系统原生)' }}
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-surface-card-sub border border-surface-border-sub">
            <span class="text-sm text-text-sub">自愈持久化状态</span>
            <span class="text-xs font-mono text-text-sub">
              %ProgramData%\DITING\dns_state.json
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
