<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import type { StatusResponse, ProviderConfig, UpstreamInfo, BootstrapConfig } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import M3Icon from '../components/M3Icon.vue';
import AppModal from '../components/AppModal.vue';
import BootstrapConfigCard from '../components/BootstrapConfigCard.vue';
import LanDnsCard from '../components/LanDnsCard.vue';

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

// 对话框状态
const isDialogOpen = ref(false);
const editingIndex = ref<number>(-1);
const formId = ref('');
const formProtocol = ref<'PLAIN' | 'DOH' | 'DOT'>('PLAIN');
const formServer = ref('');
const formUrl = ref('');
const formWeight = ref(1);

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

    // 若本地未初始化 providers，从 status 映射
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
  formId.value = `dns-server-${providers.value.length + 1}`;
  formProtocol.value = 'PLAIN';
  formServer.value = '223.5.5.5:53';
  formUrl.value = '';
  formWeight.value = 1;
  isDialogOpen.value = true;
}

function openEditDialog(index: number) {
  editingIndex.value = index;
  const p = providers.value[index];
  formId.value = p.id;
  formProtocol.value = p.protocol;
  formServer.value = p.server;
  formUrl.value = p.url || '';
  formWeight.value = p.weight || 1;
  isDialogOpen.value = true;
}

function handleDeleteNode(index: number) {
  if (providers.value.length <= 1) {
    errorMessage.value = '至少需要保留一个 DNS 服务器';
    return;
  }
  providers.value.splice(index, 1);
  saveConfig();
}

function handleSaveDialog() {
  if (!formId.value.trim() || !formServer.value.trim()) {
    errorMessage.value = '服务器名称与地址不得为空';
    return;
  }
  const item: ProviderConfig = {
    id: formId.value.trim(),
    protocol: formProtocol.value,
    server: formServer.value.trim(),
    url: formUrl.value.trim(),
    weight: formWeight.value,
  };

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
  <div class="space-y-6 pb-12 select-none">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h2 class="text-2xl font-bold tracking-tight text-text-main">
          DNS 服务器与查询策略
        </h2>
        <p class="text-sm text-text-sub">
          管理用于解析域名的 DNS 服务器，支持加密传输（DoH / DoT）与智能容灾测速。
        </p>
      </div>

      <div class="flex items-center gap-3">
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
    <div v-if="successMessage" class="flex items-center justify-between rounded-xl bg-status-success-bg border border-status-success/20 px-4 py-3 text-sm text-status-success shadow-xs">
      <div class="flex items-center gap-2">
        <M3Icon name="check_circle" :size="18" />
        <span>{{ successMessage }}</span>
      </div>
      <button @click="successMessage = ''" class="app-btn-secondary app-btn-compact">
        知道了
      </button>
    </div>

    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-status-error-bg border border-status-error/20 px-4 py-3 text-sm text-status-error shadow-xs">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button @click="errorMessage = ''" class="app-btn-secondary app-btn-compact">
        关闭
      </button>
    </div>

    <!-- 局域网 DNS 服务器配置 (类似 AdGuard Home) -->
    <LanDnsCard />

    <!-- 调度策略选择卡片 (Radio + Cards) -->
    <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs transition-colors">
      <h3 class="text-base font-bold text-text-main mb-4 flex items-center gap-2">
        <M3Icon name="upstream" :size="20" class="text-brand-primary" />
        服务器优选策略
      </h3>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          v-for="mode in schedulingModes"
          :key="mode.id"
          class="flex items-start gap-3 p-4 rounded-xl border transition-all duration-200 cursor-pointer"
          :class="[
            currentMode === mode.id
              ? 'border-brand-primary/60 bg-brand-container/20 shadow-xs'
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
          <div class="space-y-1">
            <span class="text-sm font-bold text-text-main">
              {{ mode.name }}
            </span>
            <p class="text-xs text-text-sub">
              {{ mode.desc }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- 上游节点列表 -->
    <div class="space-y-4">
      <h3 class="text-base font-bold text-text-main flex items-center gap-2">
        <M3Icon name="router" :size="20" class="text-brand-primary" />
        已添加的 DNS 服务器 ({{ upstreams.length }})
      </h3>

      <div class="space-y-3">
        <div
          v-for="(node, idx) in upstreams"
          :key="node.id"
          class="rounded-2xl border border-surface-border bg-surface-card p-5 shadow-xs transition-all duration-200 hover:shadow-md hover:border-brand-primary/30"
        >
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div class="space-y-1.5">
              <div class="flex items-center gap-3">
                <span class="text-base font-bold text-text-main font-mono">
                  {{ node.id }}
                </span>
                <span
                  class="px-2.5 py-0.5 rounded-full text-xs font-bold font-mono tracking-wider"
                  :class="[
                    node.protocol === 'DOH' ? 'bg-sky-500/15 text-sky-600 dark:text-sky-400' :
                    node.protocol === 'DOT' ? 'bg-purple-500/15 text-purple-600 dark:text-purple-400' :
                    'bg-surface-card-sub text-text-sub border border-surface-border-sub'
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
                <span class="h-8 px-2.5 rounded-lg bg-status-success-bg text-status-success border border-status-success/30 font-semibold inline-flex items-center">
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

    <!-- 新增 / 编辑节点弹窗 (统一使用 AppModal 居中架构) -->
    <AppModal
      :open="isDialogOpen"
      @close="isDialogOpen = false"
      :title="editingIndex >= 0 ? '编辑 DNS 服务器' : '添加 DNS 服务器'"
    >
      <form id="upstream-dialog-form" @submit.prevent="handleSaveDialog" class="space-y-4 pt-1">
        <md-outlined-text-field
          label="服务器名称 / 标识"
          :value="formId"
          @input="formId = ($event.target as any).value"
          class="w-full"
          required
        ></md-outlined-text-field>

        <md-outlined-select
          label="连接协议"
          :value="formProtocol"
          @change="formProtocol = ($event.target as any).value"
          class="w-full"
        >
          <md-select-option value="PLAIN">
            <div slot="headline">普通模式 (标准 DNS / 端口 53)</div>
          </md-select-option>
          <md-select-option value="DOH">
            <div slot="headline">加密模式 (DNS over HTTPS / 安全防窥探)</div>
          </md-select-option>
          <md-select-option value="DOT">
            <div slot="headline">加密模式 (DNS over TLS / 端口 853)</div>
          </md-select-option>
        </md-outlined-select>

        <md-outlined-text-field
          label="服务器地址 (IP 或域名)"
          :value="formServer"
          @input="formServer = ($event.target as any).value"
          class="w-full font-mono"
          placeholder="如 223.5.5.5:53 或 dns.alidns.com"
        ></md-outlined-text-field>

        <md-outlined-text-field
          v-if="formProtocol === 'DOH'"
          label="DoH 加密解析地址 (URL)"
          :value="formUrl"
          @input="formUrl = ($event.target as any).value"
          class="w-full font-mono"
          placeholder="https://dns.alidns.com/dns-query"
        ></md-outlined-text-field>
      </form>

      <template #actions>
        <button
          type="button"
          @click="isDialogOpen = false"
          class="app-btn-secondary"
        >
          取消
        </button>
        <button
          type="button"
          @click="handleSaveDialog"
          class="app-btn-primary"
        >
          保存服务器
        </button>
      </template>
    </AppModal>
  </div>
</template>
