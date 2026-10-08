<script setup lang="ts">
import { ref } from 'vue';
import { ipc } from '../api/ipc';
import type { BootstrapConfig, BootstrapServer } from '../api/types';
import M3Icon from './M3Icon.vue';
import AppModal from './AppModal.vue';

const props = defineProps<{
  config: BootstrapConfig;
  saving?: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:config', value: BootstrapConfig): void;
  (e: 'save', value: BootstrapConfig): void;
}>();

// 对话框表单状态
const isDialogOpen = ref(false);
const editingIndex = ref(-1);
const formId = ref('');
const formName = ref('');
const formAddress = ref('');
const formError = ref('');

// 延迟测速状态
const probingId = ref<string | null>(null);
const probeResults = ref<Record<string, number>>({});

// 常用推荐预设
const presets = [
  { name: 'AliDNS (阿里)', ip: '223.5.5.5:53' },
  { name: 'DNSPod (腾讯)', ip: '119.29.29.29:53' },
  { name: '114 DNS', ip: '114.114.114.114:53' },
  { name: 'Cloudflare', ip: '1.1.1.1:53' },
  { name: 'Google DNS', ip: '8.8.8.8:53' },
];

function applyPreset(p: { name: string; ip: string }) {
  formName.value = p.name;
  formAddress.value = p.ip;
  if (!formId.value.trim() || formId.value.startsWith('bootstrap-')) {
    formId.value = p.name.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/-+/g, '-');
  }
}

function validateIPAddress(input: string): boolean {
  const trimmed = input.trim();
  if (!trimmed) return false;

  // 提取主机部分（去掉方括号与端口）
  let host = trimmed;
  if (trimmed.startsWith('[')) {
    const endBracket = trimmed.indexOf(']');
    if (endBracket === -1) return false;
    host = trimmed.substring(1, endBracket);
  } else if (trimmed.includes(':') && trimmed.indexOf(':') === trimmed.lastIndexOf(':')) {
    // 只有一个冒号，为 IPv4:端口
    host = trimmed.split(':')[0];
  }

  // IPv4 校验 (0-255.0-255.0-255.0-255)
  const ipv4Parts = host.split('.');
  if (ipv4Parts.length === 4) {
    return ipv4Parts.every((part) => {
      if (!/^\d+$/.test(part)) return false;
      const num = parseInt(part, 10);
      return num >= 0 && num <= 255 && (part === '0' || !part.startsWith('0'));
    });
  }

  // IPv6 校验（至少含有2个冒号，十六进制字符）
  if (host.includes(':')) {
    return /^[0-9a-fA-F:]+$/.test(host);
  }

  return false;
}

function handleToggleEnabled(e: Event) {
  const target = e.target as any;
  const newEnabled = Boolean(target.selected ?? target.checked);
  const updated: BootstrapConfig = {
    ...props.config,
    enabled: newEnabled,
  };
  emit('update:config', updated);
  emit('save', updated);
}

function openAddDialog() {
  editingIndex.value = -1;
  formId.value = `bootstrap-${(props.config.servers?.length || 0) + 1}`;
  formName.value = '';
  formAddress.value = '223.5.5.5:53';
  formError.value = '';
  isDialogOpen.value = true;
}

function openEditDialog(index: number) {
  editingIndex.value = index;
  const s = props.config.servers[index];
  formId.value = s.id;
  formName.value = s.name || '';
  formAddress.value = s.address;
  formError.value = '';
  isDialogOpen.value = true;
}

function handleDelete(index: number) {
  if (props.config.servers.length <= 1) {
    alert('请至少保留一个 Bootstrap DNS 服务器');
    return;
  }
  const updatedServers = [...props.config.servers];
  updatedServers.splice(index, 1);
  const updated: BootstrapConfig = {
    ...props.config,
    servers: updatedServers,
  };
  emit('update:config', updated);
  emit('save', updated);
}

function handleSaveDialog() {
  formError.value = '';
  const addr = formAddress.value.trim();
  if (!addr) {
    formError.value = 'Bootstrap DNS 地址不得为空';
    return;
  }

  if (!validateIPAddress(addr)) {
    formError.value = '地址必须为有效的 IP 地址（IPv4 或 IPv6，如 223.5.5.5 或 119.29.29.29），不能填写域名';
    return;
  }

  const id = formId.value.trim() || `bootstrap-${Date.now()}`;
  const name = formName.value.trim() || addr;

  const item: BootstrapServer = {
    id,
    name,
    address: addr,
    weight: 1.0,
  };

  const updatedServers = [...(props.config.servers || [])];
  if (editingIndex.value >= 0) {
    updatedServers[editingIndex.value] = item;
  } else {
    updatedServers.push(item);
  }

  const updated: BootstrapConfig = {
    ...props.config,
    servers: updatedServers,
  };

  isDialogOpen.value = false;
  emit('update:config', updated);
  emit('save', updated);
}

async function handleTestLatency(s: BootstrapServer) {
  probingId.value = s.id;
  try {
    const res = await ipc.testUpstream({
      protocol: 'BOOTSTRAP',
      server: s.address,
    });
    if (res.success) {
      probeResults.value[s.id] = res.latencyMs;
    } else {
      probeResults.value[s.id] = -1;
    }
  } catch {
    probeResults.value[s.id] = -1;
  } finally {
    probingId.value = null;
  }
}
</script>

<template>
  <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs transition-all duration-200">
    <!-- 标题与状态切换 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-surface-border/60">
      <div class="space-y-1">
        <div class="flex items-center gap-2.5">
          <M3Icon name="dns" :size="22" class="text-brand-primary" />
          <h3 class="text-base font-bold text-text-main">
            Bootstrap DNS (引导解析服务器)
          </h3>
          <span
            class="px-2 py-0.5 rounded-full text-xs font-semibold"
            :class="config.enabled ? 'bg-status-success-bg text-status-success' : 'bg-surface-card-sub text-text-sub'"
          >
            {{ config.enabled ? '已启用引导' : '已停用' }}
          </span>
        </div>
        <p class="text-xs text-text-sub leading-relaxed max-w-2xl">
          用于在建立 DoT（DNS over TLS）和 DoH（DNS over HTTPS）加密连接前解析其服务器域名。优先使用此处配置的纯 IP 地址，避免因系统 DNS 不可用而导致加密 DNS 服务无法连接。
        </p>
      </div>

      <div class="flex items-center gap-3">
        <md-switch
          :selected="config.enabled"
          @change="handleToggleEnabled"
          :disabled="saving"
          title="开启或关闭 Bootstrap DNS 引导解析"
        />
        <button
          type="button"
          @click="openAddDialog"
          :disabled="saving"
          class="app-btn-secondary app-btn-compact"
        >
          <M3Icon name="add" :size="16" />
          <span>添加引导 DNS</span>
        </button>
      </div>
    </div>

    <!-- 服务器列表 -->
    <div class="mt-4 space-y-3">
      <div
        v-if="!config.servers || config.servers.length === 0"
        class="text-center py-6 text-xs text-text-sub"
      >
        未配置 Bootstrap DNS 服务器，请点击上方按钮添加。
      </div>

      <div
        v-for="(s, idx) in config.servers"
        :key="s.id"
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3.5 rounded-xl border border-surface-border bg-surface-card-sub hover:bg-surface-hover/60 transition-colors"
      >
        <div class="space-y-1">
          <div class="flex items-center gap-2">
            <span class="text-sm font-bold text-text-main">
              {{ s.name || s.id }}
            </span>
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-surface-card border border-surface-border text-brand-primary font-semibold">
              {{ s.address }}
            </span>
          </div>
          <p class="text-xs font-mono text-text-sub">
            标识: {{ s.id }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <!-- 延迟测试徽标 -->
          <span
            v-if="probeResults[s.id] !== undefined"
            class="text-xs font-mono px-2 py-1 rounded-md font-semibold inline-flex items-center"
            :class="probeResults[s.id] > 0 ? 'bg-status-success-bg text-status-success border border-status-success/30' : 'bg-status-error-bg text-status-error border border-status-error/30'"
          >
            {{ probeResults[s.id] > 0 ? `${probeResults[s.id].toFixed(1)} ms` : '超时' }}
          </span>

          <button
            type="button"
            class="app-btn-secondary app-btn-compact"
            @click="handleTestLatency(s)"
            :disabled="probingId === s.id"
            title="测试此引导服务器延迟"
          >
            <M3Icon v-if="probingId === s.id" name="refresh" class="animate-spin" :size="14" />
            <M3Icon v-else name="bolt" :size="14" />
            <span>测速</span>
          </button>

          <button
            type="button"
            @click="openEditDialog(idx)"
            class="app-btn-icon"
            title="编辑引导 DNS"
          >
            <M3Icon name="settings" :size="16" />
          </button>

          <button
            type="button"
            @click="handleDelete(idx)"
            :disabled="config.servers.length <= 1"
            class="app-btn-icon app-btn-icon-danger"
            title="删除此引导 DNS"
          >
            <M3Icon name="delete" :size="16" />
          </button>
        </div>
      </div>
    </div>

    <!-- 添加 / 编辑弹窗 -->
    <AppModal
      :open="isDialogOpen"
      @close="isDialogOpen = false"
      :title="editingIndex >= 0 ? '编辑 Bootstrap DNS 服务器' : '添加 Bootstrap DNS 服务器'"
    >
      <form id="bootstrap-dialog-form" @submit.prevent="handleSaveDialog" class="space-y-4 pt-1">
        <!-- 常用预设快捷选用 -->
        <div class="space-y-1.5">
          <label class="text-xs font-medium text-text-sub">常用公共 DNS 快捷选用：</label>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="p in presets"
              :key="p.ip"
              type="button"
              @click="applyPreset(p)"
              class="px-2.5 py-1 text-xs rounded-lg border border-surface-border bg-surface-card hover:bg-brand-primary/10 hover:border-brand-primary/40 text-text-main transition-colors"
            >
              {{ p.name }}
            </button>
          </div>
        </div>

        <md-outlined-text-field
          label="服务器显示名称"
          :value="formName"
          @input="formName = ($event.target as any).value"
          class="w-full"
          placeholder="例如：AliDNS"
        ></md-outlined-text-field>

        <md-outlined-text-field
          label="IP 地址 (支持 IPv4 / IPv6，可带端口 :53)"
          :value="formAddress"
          @input="formAddress = ($event.target as any).value"
          class="w-full font-mono"
          placeholder="223.5.5.5:53 或 119.29.29.29"
          required
        ></md-outlined-text-field>

        <div v-if="formError" class="p-2.5 rounded-lg bg-status-error-bg text-status-error text-xs flex items-center gap-1.5 border border-status-error/20">
          <M3Icon name="error" :size="16" />
          <span>{{ formError }}</span>
        </div>
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
          保存
        </button>
      </template>
    </AppModal>
  </div>
</template>
