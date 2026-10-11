<script setup lang="ts">
import { ref, watch } from 'vue';
import type { BootstrapServer } from '../../api/types';
import { BOOTSTRAP_PRESETS } from '../../constants/dnsPresets';
import AppModal from '../AppModal.vue';
import M3Icon from '../M3Icon.vue';

const props = defineProps<{
  open: boolean;
  editingItem: BootstrapServer | null;
  serverCount: number;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'save', item: BootstrapServer): void;
}>();

const formId = ref('');
const formName = ref('');
const formAddress = ref('');
const formError = ref('');

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

  let host = trimmed;
  let portStr = '';
  if (trimmed.startsWith('[')) {
    const endBracket = trimmed.indexOf(']');
    if (endBracket === -1) return false;
    host = trimmed.substring(1, endBracket);
    const rest = trimmed.substring(endBracket + 1);
    if (rest.startsWith(':')) {
      portStr = rest.substring(1);
    } else if (rest.length > 0) {
      return false;
    }
  } else if (trimmed.includes(':') && trimmed.indexOf(':') === trimmed.lastIndexOf(':')) {
    const parts = trimmed.split(':');
    host = parts[0];
    portStr = parts[1];
  }

  if (portStr) {
    if (!/^\d+$/.test(portStr)) return false;
    const p = parseInt(portStr, 10);
    if (p <= 0 || p > 65535) return false;
  }

  const ipv4Parts = host.split('.');
  if (ipv4Parts.length === 4) {
    return ipv4Parts.every((part) => {
      if (!/^\d+$/.test(part)) return false;
      const num = parseInt(part, 10);
      return num >= 0 && num <= 255 && (part === '0' || !part.startsWith('0'));
    });
  }

  if (host.includes(':')) {
    return /^[0-9a-fA-F:]+$/.test(host);
  }

  return false;
}

watch(
  () => props.open,
  (open) => {
    if (open) {
      formError.value = '';
      if (props.editingItem) {
        formId.value = props.editingItem.id;
        formName.value = props.editingItem.name || '';
        formAddress.value = props.editingItem.address;
      } else {
        formId.value = `bootstrap-${props.serverCount + 1}`;
        formName.value = '';
        formAddress.value = '223.5.5.5:53';
      }
    }
  }
);

function handleSave() {
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

  emit('save', item);
}
</script>

<template>
  <AppModal
    :open="open"
    @close="emit('close')"
    :title="editingItem ? '编辑 Bootstrap DNS 服务器' : '添加 Bootstrap DNS 服务器'"
  >
    <form id="bootstrap-dialog-form" @submit.prevent="handleSave" class="space-y-4 pt-1">
      <!-- 常用预设快捷选用 -->
      <div class="space-y-1.5">
        <label class="text-xs font-medium text-text-sub">常用公共 DNS 快捷选用：</label>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="p in BOOTSTRAP_PRESETS"
            :key="p.ip"
            type="button"
            @click="applyPreset(p)"
            class="app-btn-chip"
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

      <div v-if="formError" class="p-2.5 rounded-md bg-status-error-bg text-status-error text-xs flex items-center gap-1.5 border border-status-error/20">
        <M3Icon name="error" :size="16" />
        <span>{{ formError }}</span>
      </div>
    </form>

    <template #actions>
      <button
        type="button"
        @click="emit('close')"
        class="app-btn-secondary"
      >
        取消
      </button>
      <button
        type="button"
        @click="handleSave"
        class="app-btn-primary"
      >
        保存
      </button>
    </template>
  </AppModal>
</template>
