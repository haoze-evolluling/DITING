<script setup lang="ts">
import { ref, watch } from 'vue';
import type { ProviderConfig } from '../../api/types';
import { DNS_PRESET_PROVIDERS, type DnsProtocolType } from '../../constants/dnsPresets';
import AppModal from '../AppModal.vue';
import M3Icon from '../M3Icon.vue';

const props = defineProps<{
  open: boolean;
  editingItem: ProviderConfig | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'save', item: ProviderConfig): void;
}>();

const formId = ref('');
const formProtocol = ref<'PLAIN' | 'DOH' | 'DOT'>('DOT');
const formServer = ref('');
const formUrl = ref('');
const formWeight = ref(1);

const currentPresetProvider = ref('阿里云');
const currentPresetProtocol = ref<DnsProtocolType>('DOT');
const selectedPresetDesc = ref('阿里巴巴公共 DNS，基于 TLS 的加密解析');
const formError = ref('');

const protocolOptions = [
  { label: '普通 DNS', value: 'PLAIN' as DnsProtocolType },
  { label: '加密 DoT', value: 'DOT' as DnsProtocolType },
  { label: '加密 DoH', value: 'DOH' as DnsProtocolType },
];

function applyPreset(providerName: string, protocol: DnsProtocolType) {
  currentPresetProvider.value = providerName;
  currentPresetProtocol.value = protocol;
  const group = DNS_PRESET_PROVIDERS.find((p) => p.name === providerName);
  if (!group) return;
  const preset = group.presets[protocol];
  if (!preset) return;

  formId.value = preset.id;
  formProtocol.value = preset.protocol;
  formServer.value = preset.server;
  formUrl.value = preset.url || '';
  selectedPresetDesc.value = preset.description || '';
}

function handleProtocolSelect(proto: DnsProtocolType) {
  formProtocol.value = proto;
  currentPresetProtocol.value = proto;
  if (currentPresetProvider.value) {
    const group = DNS_PRESET_PROVIDERS.find((p) => p.name === currentPresetProvider.value);
    if (group && group.presets[proto]) {
      selectedPresetDesc.value = group.presets[proto].description || '';
    }
  }
}

watch(
  () => props.open,
  (open) => {
    if (open) {
      formError.value = '';
      if (props.editingItem) {
        const item = props.editingItem;
        formId.value = item.id;
        formProtocol.value = item.protocol;
        formServer.value = item.server;
        formUrl.value = item.url || '';
        formWeight.value = item.weight || 1;

        let matched = false;
        for (const group of DNS_PRESET_PROVIDERS) {
          for (const proto of ['PLAIN', 'DOT', 'DOH'] as DnsProtocolType[]) {
            const p = group.presets[proto];
            if (p.id === item.id || (p.server === item.server && p.protocol === item.protocol)) {
              currentPresetProvider.value = group.name;
              currentPresetProtocol.value = p.protocol;
              selectedPresetDesc.value = p.description || '';
              matched = true;
              break;
            }
          }
          if (matched) break;
        }
        if (!matched) {
          currentPresetProvider.value = '';
          currentPresetProtocol.value = item.protocol;
          selectedPresetDesc.value = '';
        }
      } else {
        applyPreset('阿里云', 'DOT');
        formWeight.value = 1;
      }
    }
  }
);

function handleSave() {
  formError.value = '';
  if (!formId.value.trim() || !formServer.value.trim()) {
    formError.value = '服务器名称与地址不得为空';
    return;
  }

  const item: ProviderConfig = {
    id: formId.value.trim(),
    protocol: formProtocol.value,
    server: formServer.value.trim(),
    url: formUrl.value.trim(),
    weight: formWeight.value,
  };

  emit('save', item);
}
</script>

<template>
  <AppModal
    :open="open"
    @close="emit('close')"
    :title="editingItem ? '编辑 DNS 服务器' : '添加 DNS 服务器'"
  >
    <form id="upstream-dialog-form" @submit.prevent="handleSave" class="space-y-4 pt-1">
      <!-- 常用推荐预设快速填入 -->
      <div class="rounded-md border border-surface-border bg-surface-card-sub p-3 space-y-2.5">
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-text-sub flex items-center gap-1.5">
            <M3Icon name="bolt" :size="14" class="text-text-main" />
            常用推荐预设 (点击快速填入):
          </span>
          <span v-if="selectedPresetDesc" class="text-[11px] text-text-sub truncate max-w-[210px]" :title="selectedPresetDesc">
            {{ selectedPresetDesc }}
          </span>
        </div>

        <!-- 服务商 Chips -->
        <div class="space-y-1">
          <div class="text-[11px] text-text-sub">服务商:</div>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="provider in DNS_PRESET_PROVIDERS"
              :key="provider.name"
              type="button"
              @click="applyPreset(provider.name, currentPresetProtocol)"
              class="app-btn-chip"
              :class="{ active: currentPresetProvider === provider.name }"
            >
              {{ provider.name }}
            </button>
          </div>
        </div>

        <!-- 协议 Chips -->
        <div class="space-y-1">
          <div class="text-[11px] text-text-sub">解析协议:</div>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="proto in protocolOptions"
              :key="proto.value"
              type="button"
              @click="applyPreset(currentPresetProvider || '阿里云', proto.value)"
              class="app-btn-chip"
              :class="{ active: currentPresetProtocol === proto.value }"
            >
              {{ proto.label }}
            </button>
          </div>
        </div>
      </div>

      <div v-if="formError" class="p-2.5 rounded-md bg-status-error-bg text-status-error text-xs flex items-center gap-1.5 border border-status-error/20">
        <M3Icon name="error" :size="16" />
        <span>{{ formError }}</span>
      </div>

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
        @change="handleProtocolSelect(($event.target as any).value)"
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
        保存服务器
      </button>
    </template>
  </AppModal>
</template>
