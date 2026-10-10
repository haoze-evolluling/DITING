<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { ipc } from '../../api/ipc';
import type { AdapterInfo, StatusResponse } from '../../api/types';
import { revertSwitch } from '../../utils/switch';
import StatusBadge from '../../components/StatusBadge.vue';
import M3Icon from '../../components/M3Icon.vue';

const adapters = ref<AdapterInfo[]>([]);
const status = ref<StatusResponse | null>(null);
const loading = ref(false);
const operatingId = ref<string | null>(null);
const errorMessage = ref('');

const takenOverAdapterIds = computed(() => {
  const set = new Set<string>();
  if (status.value?.takeover?.adapters) {
    status.value.takeover.adapters.forEach((a) => {
      set.add(a.id);
      set.add(a.name);
    });
  }
  return set;
});

async function loadData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [adapterList, statusRes] = await Promise.all([
      ipc.getAdapters(),
      ipc.getStatus(),
    ]);
    adapters.value = adapterList;
    status.value = statusRes;
  } catch (err: any) {
    errorMessage.value = err.message || '加载网卡信息失败';
  } finally {
    loading.value = false;
  }
}

function isAdapterTakenOver(adapter: AdapterInfo): boolean {
  return takenOverAdapterIds.value.has(adapter.id) || takenOverAdapterIds.value.has(adapter.name);
}

async function handleToggleAdapter(adapter: AdapterInfo, e: Event) {
  const target = e.target as any;
  const enable = Boolean(target.selected ?? target.checked);
  operatingId.value = adapter.id;
  try {
    await ipc.setAdapterTakeover(adapter.id, enable);
    await loadData();
  } catch (err: any) {
    errorMessage.value = `操作网卡 [${adapter.name}] 失败: ${err.message}`;
    revertSwitch(e, !enable);
  } finally {
    operatingId.value = null;
  }
}

async function handleTakeoverAll() {
  loading.value = true;
  try {
    await ipc.enableTakeover();
    await loadData();
  } catch (err: any) {
    errorMessage.value = err.message;
  } finally {
    loading.value = false;
  }
}

async function handleRestoreAll() {
  loading.value = true;
  try {
    await ipc.disableTakeover();
    await loadData();
  } catch (err: any) {
    errorMessage.value = err.message;
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadData();
});
</script>

<template>
  <div class="space-y-5 pb-12 select-none">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h2 class="section-title">网络连接与保护接管</h2>
        <p class="text-[12px] text-text-sub mt-1">
          已自动排除虚拟与离线网络，仅显示当前正在使用的网络连接（如 Wi-Fi 或有线网络）。
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
          <span>刷新列表</span>
        </button>
        <button
          v-if="!status?.takeover?.active"
          type="button"
          @click="handleTakeoverAll"
          :disabled="loading"
          class="app-btn-primary"
        >
          <M3Icon name="shield" :size="16" />
          <span>全部开启保护</span>
        </button>
        <button
          v-else
          type="button"
          @click="handleRestoreAll"
          :disabled="loading"
          class="app-btn-secondary"
        >
          <M3Icon name="refresh" :size="16" />
          <span>恢复系统默认</span>
        </button>
      </div>
    </div>

    <!-- 错误横幅 -->
    <div v-if="errorMessage" class="flex items-center justify-between rounded-md bg-status-error-bg border-l-2 border-accent-seal px-4 py-3 text-[13px] text-status-error">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button
        @click="errorMessage = ''"
        class="app-btn-secondary app-btn-compact"
      >
        关闭
      </button>
    </div>

    <!-- 加载中状态 -->
    <div v-if="loading && adapters.length === 0" class="flex flex-col items-center justify-center p-16 gap-4">
      <md-circular-progress indeterminate />
      <span class="text-sm text-text-sub">正在检测网络连接...</span>
    </div>

    <!-- 空网卡状态 -->
    <div v-else-if="adapters.length === 0" class="rounded-md border border-dashed border-surface-border p-12 text-center bg-surface-card">
      <M3Icon name="adapters" :size="48" class="text-text-muted mx-auto mb-3" />
      <h3 class="font-semibold text-text-main">未发现可用的网络连接</h3>
      <p class="text-sm text-text-sub mt-1">请检查 Wi-Fi 或网线是否已正常连接至网络。</p>
      <div class="mt-4">
        <button
          type="button"
          @click="loadData"
          class="app-btn-primary"
        >
          <M3Icon name="refresh" :size="16" />
          <span>重新检测</span>
        </button>
      </div>
    </div>

    <!-- 网卡列表展示 -->
    <div v-else class="space-y-4">
      <md-list class="bg-transparent p-0 rounded-md space-y-4">
        <div
          v-for="adapter in adapters"
          :key="adapter.id"
          class="rounded-md border border-surface-border bg-surface-card p-5  transition-all duration-200 hover: "
        >
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <!-- 网卡基本属性 -->
            <div class="space-y-1.5 max-w-lg">
              <div class="flex items-center gap-3">
                <span class="text-base font-bold text-text-main">
                  {{ adapter.name }}
                </span>
                <StatusBadge
                  :status="adapter.status === 'Up' ? 'active' : 'inactive'"
                  :text="adapter.status === 'Up' ? '连接正常' : (adapter.status === 'Down' ? '未连接' : (adapter.status || '未连接'))"
                  size="sm"
                />
                <StatusBadge
                  v-if="isAdapterTakenOver(adapter)"
                  status="active"
                  text="保护生效中"
                  size="sm"
                  pulse
                />
              </div>
              <p class="text-xs text-text-sub">
                {{ adapter.description }} • 默认网关: {{ adapter.gateway || '无' }}
              </p>
            </div>

            <!-- 右侧单卡接管开关 -->
            <div class="flex items-center gap-3 bg-surface-card-sub px-4 py-2 rounded-md border border-surface-border-sub">
              <span class="text-xs font-medium text-text-main">
                {{ isAdapterTakenOver(adapter) ? '保护已开启' : '未开启' }}
              </span>
              <md-switch
                :selected="isAdapterTakenOver(adapter)"
                :disabled="operatingId === adapter.id"
                @change="(e: Event) => handleToggleAdapter(adapter, e)"
              />
            </div>
          </div>

          <!-- DNS 配置对比详情 -->
          <div class="mt-4 pt-4 border-t border-surface-border grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 text-xs">
            <div class="rounded-md bg-surface-card-sub border border-surface-border-sub p-3">
              <span class="text-text-muted block mb-1">IP 地址分配方式</span>
              <span class="font-semibold text-text-main">
                {{ adapter.ipv4DHCP ? '自动获取 (DHCP)' : '手动固定 (静态 IP)' }}
              </span>
            </div>

            <div class="rounded-md bg-surface-card-sub border border-surface-border-sub p-3">
              <span class="text-text-muted block mb-1">原始 DNS 服务器</span>
              <span class="font-mono font-medium text-text-main">
                {{ adapter.ipv4DNS?.join(', ') || '自动获取 (路由器默认)' }}
              </span>
            </div>

            <div class="rounded-md bg-surface-card-sub border border-surface-border-sub p-3">
              <span class="text-text-muted block mb-1">当前实际生效 DNS</span>
              <span
                class="font-mono font-semibold"
                :class="isAdapterTakenOver(adapter) ? 'text-status-success' : 'text-text-muted'"
              >
                {{ isAdapterTakenOver(adapter) ? '本机加速保护 (127.0.0.1)' : '系统默认设置' }}
              </span>
            </div>
          </div>
        </div>
      </md-list>
    </div>
  </div>
</template>
