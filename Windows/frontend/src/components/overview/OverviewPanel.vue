<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { ipc } from '../../api/ipc';
import type { StatusResponse, WebSocketEvent, PortCheckResult } from '../../api/types';
import type { NavTab } from '../../constants/navigation';
import StatusBadge from '../StatusBadge.vue';
import MetricStrip, { type StatEntry } from '../ui/MetricStrip.vue';
import MetricChart from '../MetricChart.vue';
import M3Icon from '../M3Icon.vue';
import PortConflictModal from '../PortConflictModal.vue';
import ToastBanner from '../ToastBanner.vue';
import OverviewQuickCards from './OverviewQuickCards.vue';
import { revertSwitch, extractSwitchValue } from '../../utils/switch';
import { usePoller } from '../../composables/usePoller';
import { formatUptime } from '../../utils/format';

const emit = defineEmits<{
  (e: 'navigate', tab: NavTab): void;
}>();

const status = ref<StatusResponse | null>(null);
const loading = ref(false);
const togglingDNS = ref(false);
const togglingTakeover = ref(false);
const errorMessage = ref('');
const portConflict = ref<PortCheckResult | null>(null);
const showConflictModal = ref(false);
const recheckError = ref('');
const isRetryingConflict = ref(false);
const isAutofixing = ref(false);

const qpsHistory = ref<number[]>([]);
const latencyHistory = ref<number[]>([]);

let unsubEvents: (() => void) | null = null;
let unsubConn: (() => void) | null = null;

const dnsRunning = computed(() => Boolean(status.value?.dns?.running));
const allowLAN = computed(() => Boolean(status.value?.dns?.allowLAN));
const primaryLanIP = computed(() => status.value?.dns?.lanAddresses?.[0] || '');
const takeoverActive = computed(() => Boolean(status.value?.takeover?.active));
const activeAdaptersCount = computed(() => status.value?.takeover?.adapters?.length || 0);

const successRate = computed(() => {
  const m = status.value?.metrics;
  if (!m || m.totalQueries === 0) return '100.0%';
  const rate = (m.successQueries / m.totalQueries) * 100;
  return `${rate.toFixed(1)}%`;
});

const uptimeText = computed(() => formatUptime(status.value?.uptimeSeconds || 0));

const metricStats = computed<StatEntry[]>(() => [
  {
    label: '实时查询速率',
    value: (status.value?.metrics?.qps || 0).toFixed(1),
    unit: '次/秒',
  },
  {
    label: '平均响应耗时',
    value: (status.value?.metrics?.avgLatencyMs || 0).toFixed(1),
    unit: '毫秒',
  },
  { label: '解析成功率', value: successRate.value },
  { label: '持续运行时长', value: uptimeText.value },
]);

const formatDnsMode = computed(() => {
  const mode = status.value?.dns?.mode?.toLowerCase();
  switch (mode) {
    case 'single':
      return '单服务器模式';
    case 'primary_backup':
      return '主备自动容灾';
    case 'parallel_race':
    case 'fastest':
      return '并发极速响应';
    case 'smart_prediction':
    case 'load_balance':
      return '智能延迟优选';
    default:
      return mode || '主备自动容灾';
  }
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

async function handleStartFailure(err: any) {
  if (err.conflict) {
    portConflict.value = err.conflict;
    showConflictModal.value = true;
    recheckError.value = '';
    errorMessage.value = 'DNS 端口 (53) 被占用，请根据引导排查';
    return;
  }

  const msg = err.message || '';
  if (msg.includes('53') || msg.includes('bind') || msg.includes('Only one usage') || msg.includes('占用')) {
    try {
      const res = await ipc.checkPortConflicts();
      if (!res.available) {
        portConflict.value = res;
        showConflictModal.value = true;
        recheckError.value = '';
        errorMessage.value = 'DNS 端口 (53) 被占用，请根据引导排查';
        return;
      }
    } catch {}
  }

  errorMessage.value = `DNS 操作失败: ${err.message}`;
}

async function handleAutofix() {
  try {
    isAutofixing.value = true;
    recheckError.value = '';
    const res = await ipc.autofixPortConflicts(true);
    if (!res.available) {
      portConflict.value = res;
      recheckError.value = '自动修复执行完毕，但仍有外部进程占用 53 端口，请排查详细诊断。';
      return;
    }
    showConflictModal.value = false;
    portConflict.value = null;
    await fetchStatus();
  } catch (err: any) {
    if (err.conflict) {
      portConflict.value = err.conflict;
    }
    recheckError.value = `自动修复失败: ${err.message}`;
  } finally {
    isAutofixing.value = false;
  }
}

async function handleDowngradeLAN() {
  try {
    isRetryingConflict.value = true;
    recheckError.value = '';
    await ipc.configureLAN({ allowLAN: false });
    await ipc.startDNS();
    showConflictModal.value = false;
    portConflict.value = null;
    await fetchStatus();
  } catch (err: any) {
    if (err.conflict) {
      portConflict.value = err.conflict;
      recheckError.value = `降级启动仍遇到冲突: ${err.message}`;
    } else {
      recheckError.value = `降级操作失败: ${err.message}`;
    }
  } finally {
    isRetryingConflict.value = false;
  }
}

async function handleRetryAfterConflict() {
  try {
    isRetryingConflict.value = true;
    recheckError.value = '';
    const checkRes = await ipc.checkPortConflicts();
    const isSelfOnly =
      checkRes.conflicts &&
      checkRes.conflicts.length > 0 &&
      checkRes.conflicts.every((c) => c.isSelf);

    if (!checkRes.available && !isSelfOnly) {
      portConflict.value = checkRes;
      recheckError.value = '53 端口仍被占用中，请确认已关闭冲突程序或停止 ICS 服务后再重试。';
      return;
    }

    showConflictModal.value = false;
    portConflict.value = null;
    togglingDNS.value = true;
    await ipc.startDNS();
    await fetchStatus();
  } catch (err: any) {
    if (err.conflict) {
      portConflict.value = err.conflict;
      recheckError.value = '启动仍遇到 53 端口冲突，请排查占用进程。';
      showConflictModal.value = true;
    } else {
      recheckError.value = `启动失败: ${err.message}`;
      showConflictModal.value = true;
    }
  } finally {
    isRetryingConflict.value = false;
    togglingDNS.value = false;
  }
}

async function handleToggleDNS(e: Event) {
  const wantStart = extractSwitchValue(e);
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
    revertSwitch(e, !wantStart);
    if (wantStart) {
      await handleStartFailure(err);
    } else {
      errorMessage.value = `停止服务失败: ${err.message}`;
    }
  } finally {
    togglingDNS.value = false;
  }
}

async function handleToggleTakeover(e: Event) {
  const nextVal = extractSwitchValue(e);
  togglingTakeover.value = true;
  try {
    if (nextVal) {
      await ipc.enableTakeover();
    } else {
      await ipc.disableTakeover();
    }
    await fetchStatus();
  } catch (err: any) {
    revertSwitch(e, !nextVal);
    if (nextVal) {
      await handleStartFailure(err);
    } else {
      errorMessage.value = `网卡接管操作失败: ${err.message}`;
    }
  } finally {
    togglingTakeover.value = false;
  }
}

usePoller(fetchStatus, 5000);

onMounted(() => {
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
});

onUnmounted(() => {
  if (unsubEvents) unsubEvents();
  if (unsubConn) unsubConn();
});
</script>

<template>
  <div class="space-y-5 select-none">
    <!-- 顶部状态提示条 -->
    <ToastBanner v-if="errorMessage" :message="errorMessage" type="error">
      <template #actions>
        <button
          v-if="portConflict"
          type="button"
          @click="showConflictModal = true"
          class="app-btn-secondary app-btn-compact border-accent-seal/40 text-accent-seal"
        >
          <M3Icon name="help" :size="14" />
          <span>排查指引</span>
        </button>
        <button type="button" @click="fetchStatus" class="app-btn-secondary app-btn-compact">
          <M3Icon name="refresh" :size="14" />
          <span>重试</span>
        </button>
      </template>
    </ToastBanner>

    <!-- 双栏主网格 -->
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-5 items-start">
      <!-- 左侧主控与实时监控栏 -->
      <div class="xl:col-span-8 flex flex-col gap-4">
        <!-- 运行控制 -->
        <div class="app-panel p-4 sm:p-5">
          <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
            <div class="space-y-1.5 min-w-0">
              <div class="flex items-center gap-3 flex-wrap">
                <h3 class="section-title">运行控制</h3>
                <StatusBadge
                  :status="dnsRunning ? 'active' : 'inactive'"
                  :text="dnsRunning ? '服务运行中' : '服务已暂停'"
                  :pulse="dnsRunning"
                  size="sm"
                />
                <StatusBadge
                  v-if="allowLAN"
                  status="active"
                  :text="`局域网 DNS: ${primaryLanIP || '运行中'}`"
                  size="sm"
                />
                <StatusBadge
                  v-if="takeoverActive"
                  status="active"
                  :text="`已保护 ${activeAdaptersCount} 个网络连接`"
                  size="sm"
                />
              </div>
              <p class="text-[13px] text-text-sub max-w-xl line-clamp-2">
                谛听在后台稳定运行，提供域名解析加速、广告与威胁拦截，并具备防断网自动恢复保障。
              </p>
            </div>

            <!-- 主控制开关组 -->
            <div class="flex flex-wrap items-center gap-4 bg-surface-card-sub px-4 py-2.5 rounded-md border border-surface-border-sub lg:shrink-0">
              <!-- 本地 DNS 解析服务开关 -->
              <div class="flex items-center gap-2.5">
                <div class="flex flex-col text-right">
                  <span class="text-[13px] font-semibold text-text-main">{{ allowLAN ? '局域网服务' : '本地服务' }}</span>
                  <span class="text-[11px] text-text-muted font-mono">{{ allowLAN ? (primaryLanIP || '全网监听') : '127.0.0.1' }}</span>
                </div>
                <md-switch
                  :selected="dnsRunning"
                  :disabled="togglingDNS"
                  @change="handleToggleDNS"
                />
              </div>

              <div class="h-6 w-px bg-surface-border" />

              <!-- 网络接管开关 -->
              <div class="flex items-center gap-2.5">
                <div class="flex flex-col text-right">
                  <span class="text-[13px] font-semibold text-text-main">网络接管</span>
                  <span class="text-[11px] text-text-muted font-mono">IPv4 / IPv6</span>
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

        <!-- 实时指标带 -->
        <MetricStrip :stats="metricStats" />

        <!-- 遥测波形图表 -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <MetricChart
            label="查询速率趋势"
            :data="qpsHistory"
            unit="次/秒"
            :height="115"
          />
          <MetricChart
            label="响应延迟波动"
            :data="latencyHistory"
            strokeColor="var(--app-accent-seal)"
            unit="毫秒"
            :height="115"
          />
        </div>
      </div>

      <!-- 右侧快捷功能与监控摘要栏 -->
      <div class="xl:col-span-4">
        <OverviewQuickCards
          :status="status"
          :formatDnsMode="formatDnsMode"
          :allowLAN="allowLAN"
          :primaryLanIP="primaryLanIP"
          :takeoverActive="takeoverActive"
          @navigate="emit('navigate', $event)"
        />
      </div>
    </div>

    <!-- 53 端口占用冲突引导弹窗 -->
    <PortConflictModal
      :open="showConflictModal"
      :conflictResult="portConflict"
      :recheckError="recheckError"
      :rechecking="isRetryingConflict"
      :autofixing="isAutofixing"
      :allowLANDowngradable="allowLAN"
      @close="showConflictModal = false; recheckError = ''"
      @resolved="handleRetryAfterConflict"
      @autofix="handleAutofix"
      @downgradeLAN="handleDowngradeLAN"
    />
  </div>
</template>
