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
  qpsHistory.value.push(qps);
  if (qpsHistory.value.length > 30) qpsHistory.value.shift();

  latencyHistory.value.push(latency);
  if (latencyHistory.value.length > 30) latencyHistory.value.shift();
}

async function handleToggleDNS(e: Event) {
  const target = e.target as HTMLInputElement;
  const nextVal = target.checked;
  togglingDNS.value = true;
  try {
    if (nextVal) {
      await ipc.startDNS();
    } else {
      await ipc.stopDNS();
    }
    await fetchStatus();
  } catch (err: any) {
    errorMessage.value = err.message;
    target.checked = !nextVal;
  } finally {
    togglingDNS.value = false;
  }
}

async function handleToggleTakeover(e: Event) {
  const target = e.target as HTMLInputElement;
  const nextVal = target.checked;
  togglingTakeover.value = true;
  try {
    if (nextVal) {
      await ipc.enableTakeover();
    } else {
      await ipc.disableTakeover();
    }
    await fetchStatus();
  } catch (err: any) {
    errorMessage.value = err.message;
    target.checked = !nextVal;
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

  pollTimer = setInterval(fetchStatus, 5000);
});

onUnmounted(() => {
  if (unsubEvents) unsubEvents();
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="space-y-6 pb-12">
    <!-- 顶部状态提示条 -->
    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-rose-500/10 border border-rose-500/20 px-4 py-3 text-sm text-rose-600 dark:text-rose-400">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <md-text-button @click="fetchStatus">重试</md-text-button>
    </div>

    <!-- 核心状态总控大卡片 -->
    <div class="relative overflow-hidden rounded-3xl border border-slate-200/50 dark:border-slate-800/80 bg-gradient-to-br from-white/90 via-slate-50/80 to-slate-100/50 dark:from-slate-900/90 dark:via-slate-900/60 dark:to-slate-950/80 p-7 shadow-sm backdrop-blur">
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div class="space-y-2">
          <div class="flex items-center gap-3">
            <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
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
          <p class="text-sm text-slate-500 dark:text-slate-400 max-w-xl">
            谛听 (DITING) 双栈 DNS 内核正在 Windows 平台运行，提供毫秒级多协议上游调度、安全故障回退与崩溃状态持久化自愈。
          </p>
        </div>

        <!-- 主控制开关组 -->
        <div class="flex flex-wrap items-center gap-6 bg-slate-100/80 dark:bg-slate-800/60 p-4 rounded-2xl border border-slate-200/40 dark:border-slate-700/40">
          <!-- DNS 代理服务开关 -->
          <div class="flex items-center gap-3">
            <div class="flex flex-col text-right">
              <span class="text-sm font-semibold text-slate-800 dark:text-slate-200">DNS 代理监听</span>
              <span class="text-xs text-slate-400">127.0.0.1:53</span>
            </div>
            <md-switch
              :selected="dnsRunning"
              :disabled="togglingDNS"
              @change="handleToggleDNS"
            />
          </div>

          <div class="h-8 w-px bg-slate-200 dark:bg-slate-700" />

          <!-- 网卡接管开关 -->
          <div class="flex items-center gap-3">
            <div class="flex flex-col text-right">
              <span class="text-sm font-semibold text-slate-800 dark:text-slate-200">物理网卡接管</span>
              <span class="text-xs text-slate-400">双栈 127.0.0.1 / ::1</span>
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
        strokeColor="var(--md-sys-color-primary, #00668b)"
        gradientId="chart-grad-qps"
        unit="req/s"
      />
      <MetricChart
        label="延迟波动历史 (ms)"
        :data="latencyHistory"
        strokeColor="var(--md-sys-color-tertiary, #006a60)"
        gradientId="chart-grad-latency"
        unit="ms"
      />
    </div>

    <!-- 快捷摘要两列面板 -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- 上游节点摘要 -->
      <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-5 shadow-sm backdrop-blur">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="upstream" :size="18" class="text-slate-500" />
            <h3 class="font-semibold text-slate-800 dark:text-slate-200">当前上游调度模式</h3>
          </div>
          <md-text-button @click="emit('navigate', 'upstream')">管理配置</md-text-button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50">
            <span class="text-sm text-slate-500 dark:text-slate-400">调度策略</span>
            <span class="text-sm font-semibold text-slate-800 dark:text-slate-100 uppercase">
              {{ status?.dns?.mode || 'PRIMARY_BACKUP' }}
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50">
            <span class="text-sm text-slate-500 dark:text-slate-400">活动节点数</span>
            <span class="text-sm font-semibold text-slate-800 dark:text-slate-100">
              {{ status?.dns?.upstreams?.length || 0 }} 个上游节点
            </span>
          </div>
        </div>
      </div>

      <!-- 网卡接管简报 -->
      <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-5 shadow-sm backdrop-blur">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <M3Icon name="adapters" :size="18" class="text-slate-500" />
            <h3 class="font-semibold text-slate-800 dark:text-slate-200">物理网卡接管简报</h3>
          </div>
          <md-text-button @click="emit('navigate', 'adapters')">查看详情</md-text-button>
        </div>
        <div class="space-y-3">
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50">
            <span class="text-sm text-slate-500 dark:text-slate-400">系统接管状态</span>
            <span class="text-sm font-semibold" :class="takeoverActive ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-500'">
              {{ takeoverActive ? '已接管 (自动灾备)' : '未接管 (系统原生)' }}
            </span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50">
            <span class="text-sm text-slate-500 dark:text-slate-400">自愈持久化状态</span>
            <span class="text-xs font-mono text-slate-600 dark:text-slate-400">
              %ProgramData%\DITING\dns_state.json
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
