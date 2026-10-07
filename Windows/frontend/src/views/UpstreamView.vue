<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import type { StatusResponse, ProviderConfig, UpstreamInfo } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import M3Icon from '../components/M3Icon.vue';

const status = ref<StatusResponse | null>(null);
const currentMode = ref('primary_backup');
const providers = ref<ProviderConfig[]>([]);
const upstreams = ref<UpstreamInfo[]>([]);
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
  { id: 'single', name: '单节点 (Single)', desc: '仅使用列表中的首个可用上游节点' },
  { id: 'primary_backup', name: '主备容灾 (Primary-Backup)', desc: '优先主节点，主节点超时故障时秒级切换备用' },
  { id: 'parallel_race', name: '并发竞速 (Parallel-Race)', desc: '向全部节点并发发包，以最快返回的结果为准' },
  { id: 'smart_prediction', name: '智能预测 (Smart-Prediction)', desc: '基于 EWMA 衰减平滑延迟评分优选最优节点' },
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
  } catch (err: any) {
    errorMessage.value = err.message || '获取上游配置失败';
  } finally {
    loading.value = false;
  }
}

async function handleModeChange(mode: string) {
  currentMode.value = mode;
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
    });
    successMessage.value = '上游调度配置已成功更新并动态生效！';
    await loadData();
    setTimeout(() => {
      successMessage.value = '';
    }, 3000);
  } catch (err: any) {
    errorMessage.value = err.message || '更新上游配置失败';
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
      errorMessage.value = `节点 [${p.id}] 测试失败: ${res.error}`;
    }
  } catch (err: any) {
    errorMessage.value = `测试失败: ${err.message}`;
  } finally {
    probingId.value = null;
  }
}

function openAddDialog() {
  editingIndex.value = -1;
  formId.value = `upstream-${providers.value.length + 1}`;
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
    errorMessage.value = '至少需要保留一个上游 DNS 解析节点';
    return;
  }
  providers.value.splice(index, 1);
  saveConfig();
}

function handleSaveDialog() {
  if (!formId.value.trim() || !formServer.value.trim()) {
    errorMessage.value = '节点标识与服务器地址不得为空';
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
  <div class="space-y-6 pb-12">
    <!-- 头部操作栏 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          上游 DNS 解析节点与调度策略
        </h2>
        <p class="text-sm text-slate-500 dark:text-slate-400">
          支持 Plain (UDP/TCP 53)、DoH (HTTPS) 及 DoT (TLS) 协议，多策略智能容灾与测速。
        </p>
      </div>

      <div class="flex items-center gap-3">
        <md-outlined-button @click="loadData" :disabled="loading">
          <M3Icon name="refresh" slot="icon" :size="16" />
          刷新状态
        </md-outlined-button>
        <md-filled-button @click="openAddDialog" :disabled="saving">
          <M3Icon name="add" slot="icon" :size="16" />
          新增上游节点
        </md-filled-button>
      </div>
    </div>

    <!-- 消息横幅 -->
    <div v-if="successMessage" class="flex items-center justify-between rounded-xl bg-emerald-500/10 border border-emerald-500/20 px-4 py-3 text-sm text-emerald-600 dark:text-emerald-400">
      <div class="flex items-center gap-2">
        <M3Icon name="check_circle" :size="18" />
        <span>{{ successMessage }}</span>
      </div>
      <md-text-button @click="successMessage = ''">知道了</md-text-button>
    </div>

    <div v-if="errorMessage" class="flex items-center justify-between rounded-xl bg-rose-500/10 border border-rose-500/20 px-4 py-3 text-sm text-rose-600 dark:text-rose-400">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <md-text-button @click="errorMessage = ''">关闭</md-text-button>
    </div>

    <!-- 调度策略选择卡片 (Radio + Cards) -->
    <div class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-6 shadow-sm backdrop-blur">
      <h3 class="text-base font-bold text-slate-900 dark:text-slate-100 mb-4 flex items-center gap-2">
        <M3Icon name="upstream" :size="20" class="text-slate-500" />
        上游调度策略选择
      </h3>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          v-for="mode in schedulingModes"
          :key="mode.id"
          class="flex items-start gap-3 p-4 rounded-xl border transition-all duration-200 cursor-pointer"
          :class="[
            currentMode === mode.id
              ? 'border-primary/50 bg-primary/5 dark:bg-primary/10 shadow-sm'
              : 'border-slate-200/60 dark:border-slate-800/60 hover:bg-slate-50 dark:hover:bg-slate-800/40',
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
            <span class="text-sm font-bold text-slate-900 dark:text-slate-100">
              {{ mode.name }}
            </span>
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ mode.desc }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- 上游节点列表 -->
    <div class="space-y-4">
      <h3 class="text-base font-bold text-slate-900 dark:text-slate-100 flex items-center gap-2">
        <M3Icon name="router" :size="20" class="text-slate-500" />
        已配置上游解析节点 ({{ providers.length }})
      </h3>

      <div class="space-y-3">
        <div
          v-for="(node, idx) in providers"
          :key="node.id"
          class="rounded-2xl border border-slate-200/50 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-5 shadow-sm backdrop-blur transition-all duration-200 hover:shadow-md"
        >
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div class="space-y-1.5">
              <div class="flex items-center gap-3">
                <span class="text-base font-bold text-slate-900 dark:text-slate-100 font-mono">
                  {{ node.id }}
                </span>
                <span
                  class="px-2.5 py-0.5 rounded-full text-xs font-bold font-mono tracking-wider"
                  :class="[
                    node.protocol === 'DOH' ? 'bg-sky-500/15 text-sky-600 dark:text-sky-400' :
                    node.protocol === 'DOT' ? 'bg-purple-500/15 text-purple-600 dark:text-purple-400' :
                    'bg-slate-500/15 text-slate-600 dark:text-slate-400'
                  ]"
                >
                  {{ node.protocol }}
                </span>
                <StatusBadge
                  status="active"
                  text="就绪"
                  size="sm"
                />
              </div>

              <p class="text-xs font-mono text-slate-600 dark:text-slate-300">
                {{ node.protocol === 'DOH' ? node.url || node.server : node.server }}
              </p>
            </div>

            <!-- 操作与测速按钮 -->
            <div class="flex items-center gap-2">
              <div v-if="probeResults[node.id] !== undefined" class="mr-2 text-xs font-semibold px-2.5 py-1 rounded-lg bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                RTT: {{ probeResults[node.id].toFixed(1) }} ms
              </div>

              <md-outlined-button
                @click="handleTestNode(node)"
                :disabled="probingId === node.id"
              >
                <md-circular-progress v-if="probingId === node.id" indeterminate slot="icon" class="w-4 h-4" />
                <M3Icon v-else name="bolt" slot="icon" :size="16" />
                测速
              </md-outlined-button>

              <md-icon-button @click="openEditDialog(idx)">
                <M3Icon name="edit" :size="18" />
              </md-icon-button>

              <md-icon-button @click="handleDeleteNode(idx)" :disabled="providers.length <= 1">
                <M3Icon name="delete" :size="18" />
              </md-icon-button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 新增 / 编辑节点弹窗 (标准 M3 Dialog + Outlined Text Field + Select) -->
    <md-dialog :open="isDialogOpen" @close="isDialogOpen = false">
      <div slot="headline">
        {{ editingIndex >= 0 ? '编辑上游节点' : '新增上游 DNS 节点' }}
      </div>
      <form slot="content" id="upstream-dialog-form" method="dialog" class="space-y-4 pt-2">
        <md-outlined-text-field
          label="节点标识 ID"
          :value="formId"
          @input="formId = ($event.target as any).value"
          class="w-full"
          required
        ></md-outlined-text-field>

        <md-outlined-select
          label="传输协议"
          :value="formProtocol"
          @change="formProtocol = ($event.target as any).value"
          class="w-full"
        >
          <md-select-option value="PLAIN">
            <div slot="headline">PLAIN (标准 UDP/TCP 53)</div>
          </md-select-option>
          <md-select-option value="DOH">
            <div slot="headline">DOH (基于 HTTP/2 的 DNS over HTTPS)</div>
          </md-select-option>
          <md-select-option value="DOT">
            <div slot="headline">DOT (基于 TLS 的 DNS over TLS 853)</div>
          </md-select-option>
        </md-outlined-select>

        <md-outlined-text-field
          label="服务器地址 (host:port)"
          :value="formServer"
          @input="formServer = ($event.target as any).value"
          class="w-full font-mono"
          placeholder="如 223.5.5.5:53 或 dns.alidns.com:853"
        ></md-outlined-text-field>

        <md-outlined-text-field
          v-if="formProtocol === 'DOH'"
          label="DoH URL 地址"
          :value="formUrl"
          @input="formUrl = ($event.target as any).value"
          class="w-full font-mono"
          placeholder="https://dns.alidns.com/dns-query"
        ></md-outlined-text-field>
      </form>
      <div slot="actions">
        <md-text-button form="upstream-dialog-form" value="cancel" @click="isDialogOpen = false">取消</md-text-button>
        <md-filled-button form="upstream-dialog-form" value="save" @click="handleSaveDialog">保存节点</md-filled-button>
      </div>
    </md-dialog>
  </div>
</template>
