<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../../api/ipc';
import type { StatusResponse, ProviderConfig, UpstreamInfo, BootstrapConfig } from '../../api/types';
import StatusBadge from '../StatusBadge.vue';
import M3Icon from '../M3Icon.vue';
import BootstrapConfigCard from '../BootstrapConfigCard.vue';
import UpstreamEditModal from './UpstreamEditModal.vue';
import ConfirmModal from '../ConfirmModal.vue';

const status = ref<StatusResponse | null>(null);
const currentMode = ref('primary_backup');
const providers = ref<ProviderConfig[]>([]);
const upstreams = ref<UpstreamInfo[]>([]);
const bootstrapConfig = ref<BootstrapConfig>({
  enabled: true,
  servers: [
    { id: 'bs-ali', name: 'AliDNS', address: '223.5.5.5:53', weight: 1.0 },
    { id: 'bs-dnspod', name: 'DNSPod', address: '119.29.29.29:53', weight: 1.0 },
  ],
});
const loading = ref(false);
const saving = ref(false);
const errorMessage = ref('');
const successMessage = ref('');

// 延迟测试状态
const probingId = ref<string | null>(null);
const probeResults = ref<Record<string, number>>({});

// 编辑弹窗状态
const isDialogOpen = ref(false);
const editingItem = ref<ProviderConfig | null>(null);
const editingIndex = ref<number>(-1);

// 删除与确认弹窗
const isConfirmOpen = ref(false);
const confirmTitle = ref('');
const confirmMessage = ref('');
const deleteIndexPending = ref<number | null>(null);

const schedulingModes = [
  { id: 'single', name: '单服务器模式', desc: '始终固定使用列表中的首选服务器进行解析' },
  { id: 'primary_backup', name: '主备自动容灾', desc: '平时优先使用主服务器，超时或故障时自动切换至备用服务器' },
  { id: 'parallel_race', name: '并发极速响应', desc: '同时向全部服务器发送查询，自动采用最快返回的结果，解析延迟最低' },
  { id: 'smart_prediction', name: '智能延迟优选', desc: '根据各服务器近期响应速度与稳定性动态评分，智能选用最优质服务器' },
];

async function loadData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const res = await ipc.getStatus();
    status.value = res;
    currentMode.value = res.dns.mode.toLowerCase() || 'primary_backup';
    upstreams.value = res.dns.upstreams || [];

    if (providers.value.length === 0 && res.dns.upstreams) {
      providers.value = res.dns.upstreams.map((u) => ({
        id: u.id,
        protocol: u.protocol,
        server: u.server,
        url: u.url || (u.protocol === 'DOH' ? `https://${u.server}/dns-query` : ''),
        weight: u.weight || 1,
      }));
    }

    if (res.dns.bootstrap) {
      bootstrapConfig.value = {
        enabled: res.dns.bootstrap.enabled,
        servers: res.dns.bootstrap.servers || [],
      };
    }
  } catch (err: any) {
    errorMessage.value = err.message || '获取 DNS 配置失败';
  } finally {
    loading.value = false;
  }
}

async function handleModeChange(mode: string) {
  currentMode.value = mode;
  await saveConfig();
}

async function handleBootstrapSave(updated: BootstrapConfig) {
  bootstrapConfig.value = updated;
  await saveConfig();
}

async function saveConfig() {
  saving.value = true;
  errorMessage.value = '';
  successMessage.value = '';
  try {
    await ipc.configureUpstream({
      mode: currentMode.value.toUpperCase(),
      providers: providers.value,
      bootstrap: bootstrapConfig.value,
    });
    successMessage.value = 'DNS 服务器配置已更新并即时生效！';
    await loadData();
    setTimeout(() => {
      successMessage.value = '';
    }, 3000);
  } catch (err: any) {
    errorMessage.value = err.message || '更新 DNS 配置失败';
  } finally {
    saving.value = false;
  }
}

async function handleTestNode(p: ProviderConfig) {
  probingId.value = p.id;
  try {
    const res = await ipc.testUpstream({
      protocol: p.protocol,
      server: p.server,
      url: p.url,
    });
    if (res.success) {
      probeResults.value[p.id] = res.latencyMs;
    } else {
      errorMessage.value = `服务器 [${p.id}] 测试失败: ${res.error}`;
    }
  } catch (err: any) {
    errorMessage.value = `测试失败: ${err.message}`;
  } finally {
    probingId.value = null;
  }
}

function openAddDialog() {
  editingIndex.value = -1;
  editingItem.value = null;
  isDialogOpen.value = true;
}

function openEditDialog(index: number) {
  editingIndex.value = index;
  editingItem.value = providers.value[index] || null;
  isDialogOpen.value = true;
}

function handleDeleteNode(index: number) {
  if (providers.value.length <= 1) {
    confirmTitle.value = '提示';
    confirmMessage.value = '请至少保留一个 DNS 服务器以维持正常的域名解析服务。';
    deleteIndexPending.value = null;
    isConfirmOpen.value = true;
    return;
  }
  deleteIndexPending.value = index;
  confirmTitle.value = '确认删除';
  confirmMessage.value = `确定删除上游 DNS 服务器 [${providers.value[index]?.id || providers.value[index]?.server}] 吗？`;
  isConfirmOpen.value = true;
}

function handleConfirmAction() {
  if (deleteIndexPending.value !== null) {
    providers.value.splice(deleteIndexPending.value, 1);
    deleteIndexPending.value = null;
    saveConfig();
  }
  isConfirmOpen.value = false;
}

function handleSaveDialog(item: ProviderConfig) {
  if (editingIndex.value >= 0) {
    providers.value[editingIndex.value] = item;
  } else {
    providers.value.push(item);
  }
  isDialogOpen.value = false;
  saveConfig();
}

onMounted(() => {
  loadData();
});
</script>

<template>
  <div class="space-y-5 select-none">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="min-w-0">
        <h3 class="section-title">上游 DNS 与查询策略</h3>
        <p class="text-[13px] text-text-sub mt-0.5">
          管理用于解析域名的 DNS 服务器，支持加密传输（DoH / DoT）与智能容灾测速。
        </p>
      </div>

      <div class="flex items-center gap-2 shrink-0">
        <button
          type="button"
          @click="loadData"
          :disabled="loading"
          class="app-btn-secondary"
        >
          <M3Icon name="refresh" :size="16" :class="loading ? 'animate-spin' : ''" />
          <span>刷新状态</span>
        </button>
        <button
          type="button"
          @click="openAddDialog"
          :disabled="saving"
          class="app-btn-primary"
        >
          <M3Icon name="add" :size="16" />
          <span>添加 DNS 服务器</span>
        </button>
      </div>
    </div>

    <!-- 消息横幅 -->
    <div v-if="successMessage" class="flex items-center justify-between rounded-md bg-status-success-bg border-l-2 border-status-success px-4 py-3 text-[13px] text-status-success">
      <div class="flex items-center gap-2">
        <M3Icon name="check_circle" :size="18" />
        <span>{{ successMessage }}</span>
      </div>
      <button @click="successMessage = ''" class="app-btn-secondary app-btn-compact">
        知道了
      </button>
    </div>

    <div v-if="errorMessage" class="flex items-center justify-between rounded-md bg-status-error-bg border-l-2 border-accent-seal px-4 py-3 text-[13px] text-status-error">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button @click="errorMessage = ''" class="app-btn-secondary app-btn-compact">
        关闭
      </button>
    </div>

    <!-- 调度策略选择 -->
    <div class="app-panel p-5">
      <h4 class="section-title mb-4">服务器优选策略</h4>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div
          v-for="mode in schedulingModes"
          :key="mode.id"
          class="flex items-start gap-3 p-3.5 rounded-md border transition-colors duration-150 cursor-pointer"
          :class="[
            currentMode === mode.id
              ? 'border-brand-primary bg-brand-container/40'
              : 'border-surface-border bg-surface-card-sub hover:bg-surface-hover',
          ]"
          @click="handleModeChange(mode.id)"
        >
          <md-radio
            :checked="currentMode === mode.id"
            :value="mode.id"
            name="scheduling-mode"
            class="mt-0.5"
          />
          <div class="space-y-0.5">
            <span class="text-[13.5px] font-semibold text-text-main">
              {{ mode.name }}
            </span>
            <p class="text-[12px] text-text-sub leading-relaxed">
              {{ mode.desc }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- 上游节点列表 -->
    <div class="space-y-3">
      <h3 class="section-title">已添加的 DNS 服务器 · {{ upstreams.length }}</h3>

      <div v-if="upstreams.length === 0" class="rounded-md border border-dashed border-surface-border p-8 text-center">
        <M3Icon name="router" :size="32" class="text-text-muted mx-auto mb-2 opacity-50" />
        <p class="text-[13px] font-medium text-text-main mb-1">暂无配置 DNS 服务器</p>
        <p class="text-[12px] text-text-sub mb-4">请点击添加按钮，从预设库中快速选择并添加 DNS 服务器</p>
        <button type="button" @click="openAddDialog" class="app-btn-primary app-btn-compact mx-auto">
          <M3Icon name="add" :size="14" />
          <span>添加预设服务器</span>
        </button>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="(node, idx) in upstreams"
          :key="node.id"
          class="rounded-md border border-surface-border bg-surface-card p-5 transition-all duration-200"
        >
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div class="space-y-1.5">
              <div class="flex items-center gap-3">
                <span class="text-base font-bold text-text-main font-mono">
                  {{ node.id }}
                </span>
                <span
                  class="px-2 py-0.5 rounded-full text-[11px] font-semibold font-mono border"
                  :class="[
                    node.protocol === 'DOH'
                      ? 'border-accent-seal/50 text-accent-seal'
                      : node.protocol === 'DOT'
                        ? 'border-accent-seal/40 text-text-main'
                        : 'border-surface-border text-text-sub'
                  ]"
                >
                  {{ node.protocol === 'DOH' ? '加密 DoH' : node.protocol === 'DOT' ? '加密 DoT' : '普通 DNS' }}
                </span>
                <StatusBadge
                  :status="node.active ? 'active' : 'inactive'"
                  :text="node.active ? '连接正常' : '暂停使用'"
                  size="sm"
                />
              </div>
              <p class="text-xs font-mono text-text-sub">
                服务器地址: <span class="text-text-main font-medium">{{ node.server }}</span>
                <span v-if="node.url" class="ml-2">| 加密地址: {{ node.url }}</span>
              </p>
            </div>

            <!-- 右侧测速与操作项 -->
            <div class="flex items-center gap-2">
              <div v-if="probeResults[node.id] !== undefined" class="text-xs font-mono mr-1">
                <span class="h-8 px-2.5 rounded-md bg-status-success-bg text-status-success border border-status-success/30 font-semibold inline-flex items-center">
                  {{ probeResults[node.id].toFixed(1) }} 毫秒
                </span>
              </div>

              <button
                type="button"
                class="app-btn-secondary app-btn-compact"
                @click="handleTestNode({ id: node.id, protocol: node.protocol, server: node.server, url: node.url })"
                :disabled="probingId === node.id"
              >
                <M3Icon v-if="probingId === node.id" name="refresh" class="animate-spin" :size="14" />
                <M3Icon v-else name="bolt" :size="14" />
                <span>测试延迟</span>
              </button>

              <button
                type="button"
                @click="openEditDialog(idx)"
                class="app-btn-icon"
                title="编辑服务器"
              >
                <M3Icon name="settings" :size="16" />
              </button>

              <button
                type="button"
                @click="handleDeleteNode(idx)"
                :disabled="upstreams.length <= 1"
                class="app-btn-icon app-btn-icon-danger"
                title="删除服务器"
              >
                <M3Icon name="delete" :size="16" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Bootstrap DNS 引导解析配置卡片 -->
    <BootstrapConfigCard
      :config="bootstrapConfig"
      :saving="saving"
      @update:config="bootstrapConfig = $event"
      @save="handleBootstrapSave"
    />

    <!-- 新增 / 编辑节点弹窗 -->
    <UpstreamEditModal
      :open="isDialogOpen"
      :editingItem="editingItem"
      @close="isDialogOpen = false"
      @save="handleSaveDialog"
    />

    <!-- 删除确认弹窗 -->
    <ConfirmModal
      :open="isConfirmOpen"
      :title="confirmTitle"
      :message="confirmMessage"
      :danger="deleteIndexPending !== null"
      :confirmText="deleteIndexPending !== null ? '确定删除' : '知道了'"
      @confirm="handleConfirmAction"
      @cancel="isConfirmOpen = false"
    />
  </div>
</template>
