<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { StatusResponse, WebSocketEvent, PortCheckResult } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import MetricCard from '../components/MetricCard.vue';
import MetricChart from '../components/MetricChart.vue';
import M3Icon from '../components/M3Icon.vue';
import PortConflictModal from '../components/PortConflictModal.vue';

const emit = defineEmits<{
  (e: 'navigate', tab: string): void;
}>();

const status = ref<StatusResponse | null>(null);
const loading = ref(false);
const togglingDNS = ref(false);
const togglingTakeover = ref(false);
const errorMessage = ref('');
const portConflict = ref<PortCheckResult | null>(null);
const showConflictModal = ref(false);

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
    errorMessage.value = 'DNS 端口 (53) 被占用，请根据引导排查';
    return;
  }

  const msg = err.message || '';
  if (msg.includes('53') || msg.includes('bind') || msg.includes('Only one usage') || msg.includes('占用')) {
    try {
      const res = await ipc.checkPortConflicts();
      if (!res.available || res.hasICS || (res.conflicts && res.conflicts.length > 0)) {
        portConflict.value = res;
        showConflictModal.value = true;
        errorMessage.value = 'DNS 端口 (53) 被占用，请根据引导排查';
        return;
      }
    } catch {}
  }

  errorMessage.value = `DNS 操作失败: ${err.message}`;
}

async function handleRetryAfterConflict() {
  try {
    errorMessage.value = '';
    const checkRes = await ipc.checkPortConflicts();
    let hasOther = false;
    for (const c of (checkRes.conflicts || [])) {
      if (!c.isSelf) {
        hasOther = true;
        break;
      }
    }
    if (!checkRes.available && hasOther) {
      portConflict.value = checkRes;
      alert('53 端口仍被占用中，请确认已关闭冲突程序或停止 ICS 服务后再重试。');
      return;
    }

    showConflictModal.value = false;
    portConflict.value = null;
    togglingDNS.value = true;
    await ipc.startDNS();
    await fetchStatus();
  } catch (err: any) {
    await handleStartFailure(err);
  } finally {
    togglingDNS.value = false;
  }
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
    target.selected = dnsRunning.value;
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
    if ('selected' in target) {
      target.selected = !nextVal;
    } else {
      target.checked = !nextVal;
    }
    if (nextVal) {
      await handleStartFailure(err);
    } else {
      errorMessage.value = `网卡接管操作失败: ${err.message}`;
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
    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-status-error-bg border border-status-error/20 px-4 py-2.5 text-sm text-status-error gap-3 flex-wrap">
      <div class="flex items-center gap-2 min-w-0">
        <M3Icon name="error" :size="18" class="shrink-0" />
        <span>{{ errorMessage }}</span>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <button
          v-if="portConflict"
          type="button"
          @click="showConflictModal = true"
          class="app-btn-secondary app-btn-compact border-status-error/40 text-status-error hover:bg-status-error/10"
        >
          <M3Icon name="help" :size="14" />
          <span>排查指引</span>
        </button>
        <button
          type="button"
          @click="fetchStatus"
          class="app-btn-secondary app-btn-compact"
        >
          <M3Icon name="refresh" :size="14" />
          <span>重试</span>
        </button>
      </div>
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
                  DNS 加速与防护引擎
                </h2>
                <StatusBadge
                  :status="dnsRunning ? 'active' : 'inactive'"
                  :text="dnsRunning ? '服务运行中' : '服务已暂停'"
                  :pulse="dnsRunning"
                />
                <StatusBadge
                  v-if="takeoverActive"
                  status="active"
                  :text="`已保护 ${activeAdaptersCount} 个网络连接`"
                  size="sm"
                />
              </div>
              <p class="text-xs sm:text-sm text-text-sub max-w-xl line-clamp-2">
                谛听正在后台稳定运行，为您提供极速无感的域名解析加速、智能广告与威胁拦截，并提供防断网自动恢复保障。
              </p>
            </div>

            <!-- 主控制开关组 -->
            <div class="flex items-center gap-4 bg-surface-card-sub px-4 py-3 rounded-2xl border border-surface-border-sub shrink-0">
              <!-- 本地 DNS 解析服务开关 -->
              <div class="flex items-center gap-2.5">
                <div class="flex flex-col text-right">
                  <span class="text-xs sm:text-sm font-semibold text-text-main">本地服务</span>
                  <span class="text-[11px] text-text-muted">127.0.0.1 (本机)</span>
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
                  <span class="text-xs sm:text-sm font-semibold text-text-main">网络接管</span>
                  <span class="text-[11px] text-text-muted">IPv4 / IPv6</span>
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

        <!-- 实时指标卡片 (4 列排布) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3.5">
          <MetricCard
            title="实时查询速率"
            :value="(status?.metrics?.qps || 0).toFixed(1)"
            unit="次/秒"
            icon="speed"
            subtext="当前每秒处理量"
          />
          <MetricCard
            title="平均响应耗时"
            :value="(status?.metrics?.avgLatencyMs || 0).toFixed(1)"
            unit="毫秒"
            icon="bolt"
            subtext="服务器平均耗时"
          />
          <MetricCard
            title="解析成功率"
            :value="successRate"
            icon="check_circle"
            :subtext="`成功: ${status?.metrics?.successQueries || 0} / 失败: ${status?.metrics?.failedQueries || 0}`"
          />
          <MetricCard
            title="持续运行时长"
            :value="formatUptime"
            icon="shield"
            :subtext="`进程编号: ${status?.pid || '-'}`"
          />
        </div>

        <!-- 遥测波形图表 (双图表并列) -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <MetricChart
            label="实时查询速率趋势 (次/秒)"
            :data="qpsHistory"
            strokeColor="var(--app-brand-primary)"
            gradientId="chart-grad-qps"
            unit="次/秒"
            :height="115"
          />
          <MetricChart
            label="响应延迟波动历史 (毫秒)"
            :data="latencyHistory"
            strokeColor="var(--app-status-warning)"
            gradientId="chart-grad-latency"
            unit="毫秒"
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
              <h3 class="font-semibold text-text-main text-sm truncate">DNS 服务</h3>
            </div>
            <button
              @click="emit('navigate', 'upstream')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              管理服务器
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">工作策略</div>
              <div class="text-xs font-semibold text-text-main truncate mt-0.5">
                {{ formatDnsMode }}
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">可用节点</div>
              <div class="text-xs font-semibold text-text-main truncate mt-0.5">
                {{ status?.dns?.upstreams?.length || 0 }} 个可用
              </div>
            </div>
          </div>
        </div>

        <!-- 智能缓存摘要 -->
        <div class="rounded-2xl border border-surface-border bg-surface-card p-4 shadow-xs transition-colors">
          <div class="flex items-center justify-between gap-2 mb-2.5">
            <div class="flex items-center gap-2 min-w-0">
              <M3Icon name="cache" :size="18" class="text-brand-primary shrink-0" />
              <h3 class="font-semibold text-text-main text-sm truncate">解析加速</h3>
            </div>
            <button
              @click="emit('navigate', 'cache')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              查看详情
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">缓存命中率</div>
              <div class="text-xs font-bold text-brand-primary font-mono mt-0.5">
                {{ ((status?.cache?.hitRatio || 0) * 100).toFixed(1) }}%
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">已存记录 / 容量</div>
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
              <div class="text-[11px] text-text-sub">已拦截 / 规则数</div>
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
              <h3 class="font-semibold text-text-main text-sm truncate">网络接管</h3>
            </div>
            <button
              @click="emit('navigate', 'adapters')"
              class="app-btn-tonal app-btn-compact !px-2.5"
            >
              查看网络
            </button>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">系统网络状态</div>
              <div class="text-xs font-semibold truncate mt-0.5" :class="takeoverActive ? 'text-status-success' : 'text-text-muted'">
                {{ takeoverActive ? '已开启保护 (断网自动恢复)' : '未开启 (系统默认)' }}
              </div>
            </div>
            <div class="p-2.5 rounded-xl bg-surface-card-sub border border-surface-border-sub">
              <div class="text-[11px] text-text-sub">防断网保障</div>
              <div class="text-[11px] font-mono text-text-sub truncate mt-0.5" title="%ProgramData%\DITING\dns_state.json">
                已就绪 (异常退出自动恢复)
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 53 端口占用冲突友好引导弹窗 -->
    <PortConflictModal
      :open="showConflictModal"
      :conflictResult="portConflict"
      @close="showConflictModal = false"
      @resolved="handleRetryAfterConflict"
    />
  </div>
</template>
