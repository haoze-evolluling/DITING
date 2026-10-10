<script setup lang="ts">
import { ref } from 'vue';
import { ipc } from '../api/ipc';
import type { FilterStats, FilterConfig } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import MetricCard from '../components/MetricCard.vue';
import M3Icon from '../components/M3Icon.vue';
import ToastBanner from '../components/ToastBanner.vue';
import RuleListsPanel from '../components/RuleListsPanel.vue';
import RuleTestPanel from '../components/RuleTestPanel.vue';
import { revertSwitch } from '../utils/switch';
import { usePoller } from '../composables/usePoller';
import { useToast } from '../composables/useToast';

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
const activeTab = ref<'lists' | 'custom' | 'test' | 'config'>('lists');

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
    <div class="p-6 rounded-3xl bg-surface-card border border-surface-border shadow-xs flex flex-col md:flex-row md:items-center justify-between gap-4 transition-colors">
      <div class="flex items-center gap-4">
        <div class="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0" :class="stats.enabled ? 'bg-brand-container text-brand-primary' : 'bg-surface-card-sub text-text-muted'">
          <M3Icon name="shield" :size="28" />
        </div>
        <div>
          <div class="flex items-center gap-3">
            <h2 class="text-xl font-bold text-text-main">广告拦截与安全防护</h2>
            <StatusBadge :status="stats.enabled ? 'active' : 'inactive'" :text="stats.enabled ? '防护生效中' : '防护已暂停'" size="sm" />
          </div>
          <p class="text-xs text-text-sub mt-1">
            支持主流广告拦截与恶意网址防护规则，毫秒级快速识别并阻断弹窗广告、隐私追踪与危险网站。
          </p>
        </div>
      </div>
      <div class="flex items-center gap-4 shrink-0 bg-surface-card-sub px-4 py-2 rounded-2xl border border-surface-border-sub">
        <span class="text-xs font-medium text-text-main">总开关</span>
        <md-switch :selected="stats.enabled" @change="toggleMasterSwitch" :disabled="saving"></md-switch>
      </div>
    </div>

    <!-- KPI 统计卡片网格 -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <MetricCard title="已拦截请求" :value="stats.blockedQueries.toLocaleString()" unit="次" icon="block" />
      <MetricCard title="拦截比例" :value="stats.blockRate.toFixed(1)" unit="%" icon="speed" />
      <MetricCard title="有效防护规则" :value="stats.totalRules.toLocaleString()" unit="条" icon="shield" />
      <MetricCard title="已启用规则库" :value="stats.activeLists" unit="个" icon="adapters" />
    </div>

    <!-- 标签切换栏 -->
    <div class="flex border-b border-surface-border gap-2">
      <button
        v-for="tab in [
          { id: 'lists', icon: 'adapters', label: `规则订阅库 (${listCount})` },
          { id: 'custom', icon: 'edit', label: '自定义规则' },
          { id: 'test', icon: 'search', label: '网址拦截检测' },
          { id: 'config', icon: 'settings', label: '拦截处理方式' },
        ]"
        :key="tab.id"
        @click="activeTab = tab.id as any"
        class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2 cursor-pointer"
        :class="activeTab === tab.id ? 'border-brand-primary text-brand-primary font-bold' : 'border-transparent text-text-sub hover:text-text-main'"
      >
        <M3Icon :name="tab.icon" :size="16" />
        <span>{{ tab.label }}</span>
      </button>
    </div>

    <!-- TAB 1: 订阅规则源列表 -->
    <RuleListsPanel
      v-if="activeTab === 'lists'"
      @error="(m) => showToast(m, true)"
      @success="(m) => showToast(m)"
      @changed="fetchData"
    />

    <!-- TAB 2: 自定义规则编辑器 -->
    <div v-if="activeTab === 'custom'" class="space-y-4">
      <div class="p-4 rounded-2xl bg-surface-card border border-surface-border text-xs text-text-sub space-y-1 shadow-xs">
        <div class="font-bold text-text-main mb-1 flex items-center gap-2">
          <M3Icon name="info" :size="14" class="text-brand-primary" />
          <span>常用规则编写指南</span>
        </div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-brand-primary font-mono">||example.com^</code> 拦截该网站及其所有子域名</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-brand-primary font-mono">@@||safe.com^</code> 白名单信任放行 (允许访问该网站)</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-brand-primary font-mono">0.0.0.0 bad.com</code> 兼容传统 Hosts 文件拦截格式</div>
        <div>• <code class="bg-surface-card-sub px-1 py-0.5 rounded text-brand-primary font-mono">||urgent.com^$important</code> 强制拦截 (最高优先级，忽略白名单)</div>
      </div>

      <div class="rounded-2xl border border-surface-border bg-surface-card p-2 focus-within:ring-2 focus-within:ring-brand-primary/40 shadow-xs">
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
      <div class="p-6 rounded-2xl bg-surface-card border border-surface-border space-y-5 shadow-xs">
        <div>
          <h3 class="text-base font-bold text-text-main">拦截处理方式</h3>
          <p class="text-xs text-text-sub mt-1">选择当遇到被拦截的广告或恶意网址时，向系统和浏览器返回的处理方式</p>
        </div>

        <div class="space-y-3 text-sm">
          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-surface-hover transition-colors">
            <input type="radio" v-model="config.blockMode" value="null_ip" class="accent-brand-primary" />
            <div>
              <div class="font-medium text-text-main">直接拦截 (推荐)</div>
              <div class="text-xs text-text-sub">立即返回空地址，以最快速度终止广告加载且不会引起网页反复重试</div>
            </div>
          </label>

          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-surface-hover transition-colors">
            <input type="radio" v-model="config.blockMode" value="nxdomain" class="accent-brand-primary" />
            <div>
              <div class="font-medium text-text-main">提示域名不存在 (NXDOMAIN)</div>
              <div class="text-xs text-text-sub">告知浏览器该网址不存在，部分软件会放弃进一步连接</div>
            </div>
          </label>

          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-surface-hover transition-colors">
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
