<script setup lang="ts">
import { ref, computed } from 'vue';
import { ipc } from '../../api/ipc';
import type { FilterStats, FilterConfig } from '../../api/types';
import StatusBadge from '../../components/StatusBadge.vue';
import M3Icon from '../../components/M3Icon.vue';
import MetricStrip, { type StatEntry } from '../../components/ui/MetricStrip.vue';
import ToastBanner from '../../components/ToastBanner.vue';
import RuleListsPanel from '../../components/RuleListsPanel.vue';
import RuleTestPanel from '../../components/RuleTestPanel.vue';
import { revertSwitch } from '../../utils/switch';
import { usePoller } from '../../composables/usePoller';
import { useToast } from '../../composables/useToast';

const stats = ref<FilterStats>({
  enabled: true,
  totalRules: 0,
  activeLists: 0,
  totalQueries: 0,
  blockedQueries: 0,
  allowedQueries: 0,
  blockRate: 0,
});

const config = ref<FilterConfig>({
  enabled: true,
  blockMode: 'null_ip',
  blockingIPv4: '0.0.0.0',
  blockingIPv6: '::',
  customRules: [],
  lists: [],
  updateIntervalHours: 24,
});

const listCount = ref(0);
const customRulesText = ref('');
/** 子页签由上层 RulesView 的分段控件驱动（hash 可直达） */
const activeTab = defineModel<string>('sub', { default: 'lists' });

const ruleStats = computed<StatEntry[]>(() => [
  { label: '已拦截请求', value: stats.value.blockedQueries.toLocaleString(), unit: '次', tone: 'seal' },
  { label: '拦截比例', value: stats.value.blockRate.toFixed(1), unit: '%' },
  { label: '有效防护规则', value: stats.value.totalRules.toLocaleString(), unit: '条' },
  { label: '已启用规则库', value: stats.value.activeLists, unit: '个' },
]);

const saving = ref(false);
const { toast, show: showToast, dismiss } = useToast();

async function fetchData() {
  try {
    const [st, cfg, l, rules] = await Promise.all([
      ipc.getFilterStats(),
      ipc.getFilterConfig(),
      ipc.getFilterLists(),
      ipc.getCustomRules(),
    ]);
    if (st) stats.value = st;
    if (cfg) config.value = cfg;
    listCount.value = (l || []).length;
    customRulesText.value = (rules || []).join('\n');
  } catch (err: any) {
    showToast(err?.message || '获取规则数据失败', true);
  }
}

async function toggleMasterSwitch(e: Event) {
  const nextVal = Boolean((e.target as any).selected ?? (e.target as any).checked ?? !stats.value.enabled);
  try {
    saving.value = true;
    await ipc.updateFilterConfig({ enabled: nextVal });
    stats.value.enabled = nextVal;
    config.value.enabled = nextVal;
    showToast(`规则拦截防护已${nextVal ? '开启' : '关闭'}`);
  } catch (err: any) {
    revertSwitch(e, !nextVal);
    showToast(err?.message || '更新开关失败', true);
  } finally {
    saving.value = false;
  }
}

async function saveCustomRules() {
  try {
    saving.value = true;
    const lines = customRulesText.value
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l.length > 0);
    await ipc.setCustomRules(lines);
    showToast(`自定义规则已保存生效 (共 ${lines.length} 条)`);
    await fetchData();
  } catch (err: any) {
    showToast(err?.message || '保存自定义规则失败', true);
  } finally {
    saving.value = false;
  }
}

async function saveConfig() {
  try {
    saving.value = true;
    await ipc.updateFilterConfig({
      blockMode: config.value.blockMode,
      blockingIPv4: config.value.blockingIPv4,
      blockingIPv6: config.value.blockingIPv6,
      updateIntervalHours: Number(config.value.updateIntervalHours) || 24,
    });
    showToast('拦截策略配置已保存');
    await fetchData();
  } catch (err: any) {
    showToast(err?.message || '保存策略失败', true);
  } finally {
    saving.value = false;
  }
}

usePoller(fetchData, 4000);
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12 select-none">
    <!-- 顶部消息提示 -->
    <ToastBanner v-if="toast" :message="toast.message" :type="toast.isError ? 'error' : 'success'" dismissible @dismiss="dismiss" />

    <!-- 顶栏核心主控卡片 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <div class="flex items-center gap-2.5">
          <h2 class="section-title">广告拦截与安全防护</h2>
          <StatusBadge :status="stats.enabled ? 'active' : 'inactive'" :text="stats.enabled ? '防护生效中' : '防护已暂停'" size="sm" />
        </div>
        <p class="text-[12px] text-text-sub mt-1">
          支持主流广告拦截与恶意网址防护规则，毫秒级快速识别并阻断弹窗广告、隐私追踪与危险网站。
        </p>
      </div>
      <div class="flex items-center gap-3 shrink-0 md:pl-4">
        <span class="text-[12px] font-medium text-text-sub">总开关</span>
        <md-switch :selected="stats.enabled" @change="toggleMasterSwitch" :disabled="saving"></md-switch>
      </div>
    </div>

    <!-- 拦截指标带 -->
    <MetricStrip :stats="ruleStats" />

    <!-- TAB 1: 订阅规则源列表 -->
    <RuleListsPanel
      v-if="activeTab === 'lists'"
      @error="(m) => showToast(m, true)"
      @success="(m) => showToast(m)"
      @changed="fetchData"
    />

    <!-- TAB 2: 自定义规则编辑器 -->
    <div v-if="activeTab === 'custom'" class="space-y-4">
      <div class="p-4 rounded-md bg-surface-card border border-surface-border text-xs text-text-sub space-y-1 ">
        <div class="font-bold text-text-main mb-1 flex items-center gap-2">
          <M3Icon name="info" :size="14" class="text-text-main" />
          <span>常用规则编写指南</span>
        </div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-text-main font-mono">||example.com^</code> 拦截该网站及其所有子域名</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-text-main font-mono">@@||safe.com^</code> 白名单信任放行 (允许访问该网站)</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-text-main font-mono">0.0.0.0 bad.com</code> 兼容传统 Hosts 文件拦截格式</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-text-main font-mono">||urgent.com^$important</code> 强制拦截 (最高优先级，忽略白名单)</div>
      </div>

      <div class="rounded-md border border-surface-border bg-surface-card p-2 focus-within:border-accent-seal ">
        <textarea
          v-model="customRulesText"
          rows="14"
          placeholder="在此输入自定义拦截或信任规则，每行一条..."
          class="w-full bg-transparent border-0 resize-y p-2 text-xs font-mono text-text-main focus:outline-none"
        ></textarea>
      </div>

      <div class="flex items-center justify-end gap-3">
        <button type="button" @click="saveCustomRules" :disabled="saving" class="app-btn-primary">
          <M3Icon name="check" :size="16" />
          <span>{{ saving ? '保存中...' : '保存自定义规则' }}</span>
        </button>
      </div>
    </div>

    <!-- TAB 3: 域名规则检测工具 -->
    <RuleTestPanel v-if="activeTab === 'test'" @error="(m) => showToast(m, true)" />

    <!-- TAB 4: 策略配置 -->
    <div v-if="activeTab === 'config'" class="space-y-4 max-w-2xl">
      <div class="p-6 rounded-md bg-surface-card border border-surface-border space-y-5 ">
        <div>
          <h3 class="section-title">拦截处理方式</h3>
          <p class="text-xs text-text-sub mt-1">选择当遇到被拦截的广告或恶意网址时，向系统和浏览器返回的处理方式</p>
        </div>

        <div class="space-y-3 text-sm">
          <label
            class="flex items-center gap-3 cursor-pointer p-3 rounded-md border transition-colors"
            :class="config.blockMode === 'null_ip' ? 'bg-brand-container/40 border-brand-primary/30' : 'border-transparent hover:bg-surface-hover'"
          >
            <input type="radio" v-model="config.blockMode" value="null_ip" class="accent-brand-primary" />
            <div>
              <div class="font-medium text-text-main">直接拦截 (推荐)</div>
              <div class="text-xs text-text-sub">立即返回空地址，以最快速度终止广告加载且不会引起网页反复重试</div>
            </div>
          </label>

          <label
            class="flex items-center gap-3 cursor-pointer p-3 rounded-md border transition-colors"
            :class="config.blockMode === 'nxdomain' ? 'bg-brand-container/40 border-brand-primary/30' : 'border-transparent hover:bg-surface-hover'"
          >
            <input type="radio" v-model="config.blockMode" value="nxdomain" class="accent-brand-primary" />
            <div>
              <div class="font-medium text-text-main">提示域名不存在 (NXDOMAIN)</div>
              <div class="text-xs text-text-sub">告知浏览器该网址不存在，部分软件会放弃进一步连接</div>
            </div>
          </label>

          <label
            class="flex items-center gap-3 cursor-pointer p-3 rounded-md border transition-colors"
            :class="config.blockMode === 'refused' ? 'bg-brand-container/40 border-brand-primary/30' : 'border-transparent hover:bg-surface-hover'"
          >
            <input type="radio" v-model="config.blockMode" value="refused" class="accent-brand-primary" />
            <div>
              <div class="font-medium text-text-main">直接拒绝请求 (REFUSED)</div>
              <div class="text-xs text-text-sub">告知请求被安全策略明确拒绝</div>
            </div>
          </label>
        </div>

        <div class="pt-4 border-t border-surface-border flex justify-end">
          <button type="button" @click="saveConfig" :disabled="saving" class="app-btn-primary">
            <M3Icon name="check" :size="16" />
            <span>{{ saving ? '保存中...' : '保存策略' }}</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
