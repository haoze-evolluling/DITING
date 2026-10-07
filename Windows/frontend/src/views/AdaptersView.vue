<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { AdapterInfo, StatusResponse } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import M3Icon from '../components/M3Icon.vue';

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
  const target = e.target as HTMLInputElement;
  const enable = target.checked;
  operatingId.value = adapter.id;
  try {
    await ipc.setAdapterTakeover(adapter.id, enable);
    await loadData();
  } catch (err: any) {
    errorMessage.value = `操作网卡 [${adapter.name}] 失败: ${err.message}`;
    target.checked = !enable;
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
  <div class="space-y-6 pb-12">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          物理网卡与 DNS 接管
        </h2>
        <p class="text-sm text-slate-500 dark:text-slate-400">
          已自动过滤虚拟网卡 (WSL/Hyper-V/VPN)，仅呈现具默认网关的真实活动物理网卡。
        </p>
      </div>

      <div class="flex items-center gap-3">
        <md-outlined-button @click="loadData" :disabled="loading">
          <M3Icon name="refresh" slot="icon" :size="16" />
          刷新网卡
        </md-outlined-button>
        <md-filled-button v-if="!status?.takeover?.active" @click="handleTakeoverAll" :disabled="loading">
          <M3Icon name="shield" slot="icon" :size="16" />
          全量接管
        </md-filled-button>
        <md-outlined-button v-else @click="handleRestoreAll" :disabled="loading">
          <M3Icon name="refresh" slot="icon" :size="16" />
          全量还原
        </md-outlined-button>
      </div>
    </div>

    <!-- 错误横幅 -->
    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-rose-500/10 border border-rose-500/20 px-4 py-3 text-sm text-rose-600 dark:text-rose-400">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <md-text-button @click="errorMessage = ''">关闭</md-text-button>
    </div>

    <!-- 加载中状态 -->
    <div v-if="loading && adapters.length === 0" class="flex flex-col items-center justify-center p-16 gap-4">
      <md-circular-progress indeterminate />
      <span class="text-sm text-slate-500">正在扫描 Windows 物理网络适配器...</span>
    </div>

    <!-- 空网卡状态 -->
    <div v-else-if="adapters.length === 0" class="rounded-2xl border border-dashed border-slate-300 dark:border-slate-800 p-12 text-center">
      <M3Icon name="adapters" :size="48" class="text-slate-400 mx-auto mb-3" />
      <h3 class="font-semibold text-slate-700 dark:text-slate-300">未发现活动的物理网卡</h3>
      <p class="text-sm text-slate-500 mt-1">请检查 Wi-Fi 或以太网连接是否已正常接入互联网。</p>
      <div class="mt-4">
        <md-filled-button @click="loadData">重新扫描</md-filled-button>
      </div>
    </div>

    <!-- 网卡列表展示 -->
    <div v-else class="space-y-4">
      <md-list class="bg-transparent p-0 rounded-2xl space-y-4">
        <div
          v-for="adapter in adapters"
          :key="adapter.id"
          class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-5 shadow-sm backdrop-blur transition-all duration-200 hover:shadow-md"
        >
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <!-- 网卡基本属性 -->
            <div class="space-y-1.5 max-w-lg">
              <div class="flex items-center gap-3">
                <span class="text-base font-bold text-slate-900 dark:text-slate-100">
                  {{ adapter.name }}
                </span>
                <StatusBadge
                  :status="adapter.status === 'Up' ? 'active' : 'inactive'"
                  :text="adapter.status === 'Up' ? '连接正常' : adapter.status"
                  size="sm"
                />
                <StatusBadge
                  v-if="isAdapterTakenOver(adapter)"
                  status="active"
                  text="谛听接管生效中"
                  size="sm"
                  pulse
                />
              </div>
              <p class="text-xs text-slate-500 dark:text-slate-400">
                {{ adapter.description }} • 网关: {{ adapter.gateway || '无' }} • 索引: #{{ adapter.index }}
              </p>
            </div>

            <!-- 右侧单卡接管开关 -->
            <div class="flex items-center gap-3 bg-slate-100/60 dark:bg-slate-800/50 px-4 py-2 rounded-xl">
              <span class="text-xs font-medium text-slate-600 dark:text-slate-300">
                {{ isAdapterTakenOver(adapter) ? '接管运行' : '未接管' }}
              </span>
              <md-switch
                :selected="isAdapterTakenOver(adapter)"
                :disabled="operatingId === adapter.id"
                @change="(e: Event) => handleToggleAdapter(adapter, e)"
              />
            </div>
          </div>

          <!-- DNS 配置对比详情 -->
          <div class="mt-4 pt-4 border-t border-slate-200/40 dark:border-slate-800/60 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 text-xs">
            <div class="rounded-xl bg-slate-50/70 dark:bg-slate-950/40 p-3">
              <span class="text-slate-400 block mb-1">IPv4 获取模式</span>
              <span class="font-semibold text-slate-700 dark:text-slate-200">
                {{ adapter.ipv4DHCP ? '动态 DHCP' : '静态分配 (Static)' }}
              </span>
            </div>

            <div class="rounded-xl bg-slate-50/70 dark:bg-slate-950/40 p-3">
              <span class="text-slate-400 block mb-1">原有 IPv4 DNS 地址</span>
              <span class="font-mono font-medium text-slate-700 dark:text-slate-200">
                {{ adapter.ipv4DNS?.join(', ') || '从 DHCP 继承' }}
              </span>
            </div>

            <div class="rounded-xl bg-slate-50/70 dark:bg-slate-950/40 p-3">
              <span class="text-slate-400 block mb-1">当前接管 DNS 指向</span>
              <span
                class="font-mono font-semibold"
                :class="isAdapterTakenOver(adapter) ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400'"
              >
                {{ isAdapterTakenOver(adapter) ? '127.0.0.1 / ::1 (双栈)' : '系统默认上游' }}
              </span>
            </div>
          </div>
        </div>
      </md-list>
    </div>
  </div>
</template>
