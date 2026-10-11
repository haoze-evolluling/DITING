<script setup lang="ts">
import { ref } from 'vue';
import { ipc } from '../api/ipc';
import type { BootstrapConfig, BootstrapServer } from '../api/types';
import M3Icon from './M3Icon.vue';
import BootstrapEditModal from './network/BootstrapEditModal.vue';
import ConfirmModal from './ConfirmModal.vue';
import { useConfirmModal } from '../composables/useConfirmModal';
import { extractSwitchValue } from '../utils/switch';

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
const editingItem = ref<BootstrapServer | null>(null);
const editingIndex = ref(-1);

const {
  isOpen: isConfirmOpen,
  options: confirmOptions,
  ask: askConfirm,
  handleConfirm: handleConfirmAction,
  handleCancel: handleCancelAction,
} = useConfirmModal();

// 延迟测速状态
const probingId = ref<string | null>(null);
const probeResults = ref<Record<string, number>>({});

function handleToggleEnabled(e: Event) {
  const newEnabled = extractSwitchValue(e);
  const updated: BootstrapConfig = {
    ...props.config,
    enabled: newEnabled,
  };
  emit('update:config', updated);
  emit('save', updated);
}

function openAddDialog() {
  editingIndex.value = -1;
  editingItem.value = null;
  isDialogOpen.value = true;
}

function openEditDialog(index: number) {
  editingIndex.value = index;
  editingItem.value = props.config.servers[index] || null;
  isDialogOpen.value = true;
}

async function handleDelete(index: number) {
  if (props.config.servers.length <= 1) {
    await askConfirm({
      title: '提示',
      message: '请至少保留一个 Bootstrap DNS 服务器，避免加密握手域名无法解析。',
      confirmText: '知道了',
      showCancel: false,
    });
    return;
  }
  const target = props.config.servers[index];
  const confirmed = await askConfirm({
    title: '确认删除',
    message: `确定删除引导服务器 [${target?.name || target?.address}] 吗？`,
    danger: true,
    confirmText: '确定删除',
  });
  if (!confirmed) return;
  const updatedServers = [...props.config.servers];
  updatedServers.splice(index, 1);
  const updated: BootstrapConfig = {
    ...props.config,
    servers: updatedServers,
  };
  emit('update:config', updated);
  emit('save', updated);
}

function handleSaveServer(item: BootstrapServer) {
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
  <div class="rounded-md border border-surface-border bg-surface-card p-5 transition-all duration-200">
    <!-- 标题与状态切换 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-surface-border/60">
      <div class="space-y-1">
        <div class="flex items-center gap-2.5">
          <M3Icon name="dns" :size="22" class="text-text-main" />
          <h3 class="section-title">
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
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3.5 rounded-md border border-surface-border bg-surface-card-sub hover:bg-surface-hover/60 transition-colors"
      >
        <div class="space-y-1">
          <div class="flex items-center gap-2">
            <span class="text-sm font-bold text-text-main">
              {{ s.name || s.id }}
            </span>
            <span class="text-xs font-mono px-2 py-0.5 rounded bg-surface-card border border-surface-border text-text-main font-semibold">
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
    <BootstrapEditModal
      :open="isDialogOpen"
      :editingItem="editingItem"
      :serverCount="config.servers?.length || 0"
      @close="isDialogOpen = false"
      @save="handleSaveServer"
    />

    <!-- 确认 / 告警弹窗 -->
    <ConfirmModal
      :open="isConfirmOpen"
      :title="confirmOptions.title"
      :message="confirmOptions.message"
      :danger="confirmOptions.danger"
      :confirmText="confirmOptions.confirmText"
      :cancelText="confirmOptions.cancelText"
      :showCancel="confirmOptions.showCancel"
      @confirm="handleConfirmAction"
      @cancel="handleCancelAction"
    />
  </div>
</template>
