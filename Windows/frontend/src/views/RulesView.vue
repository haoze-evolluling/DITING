<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { FilterStats, FilterConfig, FilterList, CheckHostResult } from '../api/types';
import StatusBadge from '../components/StatusBadge.vue';
import MetricCard from '../components/MetricCard.vue';
import M3Icon from '../components/M3Icon.vue';

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

const lists = ref<FilterList[]>([]);
const customRulesText = ref('');
const activeTab = ref<'lists' | 'custom' | 'test' | 'config'>('lists');

// 规则测试工具状态
const testDomain = ref('');
const testQType = ref('A');
const testResult = ref<CheckHostResult | null>(null);
const testing = ref(false);

// 添加订阅源弹窗状态
const isAddModalOpen = ref(false);
const newListName = ref('');
const newListURL = ref('');

const loading = ref(false);
const saving = ref(false);
const refreshing = ref(false);
const errorMessage = ref('');
const successMessage = ref('');

let pollTimer: any = null;

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
    if (l) lists.value = l;
    if (rules) customRulesText.value = rules.join('\n');
  } catch (err: any) {
    errorMessage.value = err?.message || '获取规则数据失败';
  }
}

async function toggleMasterSwitch(e: Event) {
  const target = e.target as HTMLInputElement;
  const nextVal = target.checked ?? !stats.value.enabled;
  try {
    saving.value = true;
    await ipc.updateFilterConfig({ enabled: nextVal });
    stats.value.enabled = nextVal;
    config.value.enabled = nextVal;
    showToast(`规则拦截防护已${nextVal ? '开启' : '关闭'}`);
  } catch (err: any) {
    showToast(err?.message || '更新开关失败', true);
  } finally {
    saving.value = false;
  }
}

async function handleAddList() {
  if (!newListURL.value.trim()) {
    showToast('请输入有效的规则源 URL 或本地文件路径', true);
    return;
  }
  try {
    saving.value = true;
    const name = newListName.value.trim() || `订阅列表 ${lists.value.length + 1}`;
    await ipc.addFilterList({
      name,
      url: newListURL.value.trim(),
      enabled: true,
    });
    showToast('规则订阅源已添加并开始拉取');
    isAddModalOpen.value = false;
    newListName.value = '';
    newListURL.value = '';
    await fetchData();
  } catch (err: any) {
    showToast(err?.message || '添加订阅源失败', true);
  } finally {
    saving.value = false;
  }
}

async function toggleList(list: FilterList) {
  try {
    list.enabled = !list.enabled;
    await ipc.updateFilterList(list);
    showToast(`已${list.enabled ? '启用' : '禁用'}规则源: ${list.name}`);
    await fetchData();
  } catch (err: any) {
    list.enabled = !list.enabled;
    showToast(err?.message || '切换规则源状态失败', true);
  }
}

async function deleteList(id: string) {
  if (!confirm('确定要移除此规则订阅源吗？')) return;
  try {
    await ipc.deleteFilterList(id);
    showToast('已删除订阅源');
    await fetchData();
  } catch (err: any) {
    showToast(err?.message || '删除失败', true);
  }
}

async function refreshList(id?: string) {
  try {
    refreshing.value = true;
    await ipc.refreshFilterLists(id);
    showToast(id ? '规则源已更新重构' : '全量规则源拉取与索引重构完成');
    await fetchData();
  } catch (err: any) {
    showToast(err?.message || '拉取规则失败', true);
  } finally {
    refreshing.value = false;
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

async function runDomainTest() {
  if (!testDomain.value.trim()) return;
  try {
    testing.value = true;
    testResult.value = await ipc.checkHost(testDomain.value.trim(), testQType.value);
  } catch (err: any) {
    showToast(err?.message || '规则检测异常', true);
  } finally {
    testing.value = false;
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

function showToast(msg: string, isError = false) {
  if (isError) {
    errorMessage.value = msg;
    setTimeout(() => { errorMessage.value = ''; }, 4000);
  } else {
    successMessage.value = msg;
    setTimeout(() => { successMessage.value = ''; }, 3000);
  }
}

function formatTime(ms: number): string {
  if (!ms) return '未更新';
  const d = new Date(ms);
  return `${d.getMonth() + 1}-${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
}

onMounted(() => {
  fetchData();
  pollTimer = setInterval(fetchData, 4000);
});

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部消息提示 -->
    <div v-if="errorMessage" class="p-4 rounded-2xl bg-error/10 text-error border border-error/20 flex items-center justify-between text-sm animate-fade-in">
      <div class="flex items-center gap-2">
        <M3Icon name="error" :size="18" />
        <span>{{ errorMessage }}</span>
      </div>
      <button @click="errorMessage = ''" class="hover:opacity-70"><M3Icon name="close" :size="16" /></button>
    </div>

    <div v-if="successMessage" class="p-4 rounded-2xl bg-primary/10 text-primary border border-primary/20 flex items-center justify-between text-sm animate-fade-in">
      <div class="flex items-center gap-2">
        <M3Icon name="check_circle" :size="18" />
        <span>{{ successMessage }}</span>
      </div>
      <button @click="successMessage = ''" class="hover:opacity-70"><M3Icon name="close" :size="16" /></button>
    </div>

    <!-- 顶栏核心主控卡片 -->
    <div class="p-6 rounded-3xl bg-surface-container-low border border-slate-200/60 dark:border-slate-800 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
      <div class="flex items-center gap-4">
        <div class="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0" :class="stats.enabled ? 'bg-primary/15 text-primary' : 'bg-slate-200 dark:bg-slate-800 text-slate-400'">
          <M3Icon name="shield" :size="28" />
        </div>
        <div>
          <div class="flex items-center gap-3">
            <h2 class="text-xl font-bold text-slate-900 dark:text-slate-100">规则过滤与广告拦截</h2>
            <StatusBadge :status="stats.enabled ? 'active' : 'inactive'" :text="stats.enabled ? '防护保护中' : '防护已暂停'" size="sm" />
          </div>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
            支持 AdGuard / hosts 语法规则解析、倒序 Trie 树匹配与 BloomFilter 纳秒预检
          </p>
        </div>
      </div>
      <div class="flex items-center gap-4 shrink-0">
        <span class="text-xs font-medium text-slate-600 dark:text-slate-400">总开关</span>
        <md-switch :selected="stats.enabled" @change="toggleMasterSwitch" :disabled="saving"></md-switch>
      </div>
    </div>

    <!-- KPI 统计卡片网格 -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <MetricCard title="拦截请求数" :value="stats.blockedQueries.toLocaleString()" unit="次" icon="block" />
      <MetricCard title="拦截率" :value="stats.blockRate.toFixed(1)" unit="%" icon="speed" />
      <MetricCard title="生效规则总数" :value="stats.totalRules.toLocaleString()" unit="条" icon="shield" />
      <MetricCard title="活跃规则源" :value="stats.activeLists" unit="个" icon="adapters" />
    </div>

    <!-- 标签切换栏 -->
    <div class="flex border-b border-slate-200/60 dark:border-slate-800 gap-2">
      <button
        @click="activeTab = 'lists'"
        class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2"
        :class="activeTab === 'lists' ? 'border-primary text-primary' : 'border-transparent text-slate-500 hover:text-slate-800 dark:hover:text-slate-200'"
      >
        <M3Icon name="adapters" :size="16" />
        <span>订阅规则源 ({{ lists.length }})</span>
      </button>
      <button
        @click="activeTab = 'custom'"
        class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2"
        :class="activeTab === 'custom' ? 'border-primary text-primary' : 'border-transparent text-slate-500 hover:text-slate-800 dark:hover:text-slate-200'"
      >
        <M3Icon name="edit" :size="16" />
        <span>自定义规则</span>
      </button>
      <button
        @click="activeTab = 'test'"
        class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2"
        :class="activeTab === 'test' ? 'border-primary text-primary' : 'border-transparent text-slate-500 hover:text-slate-800 dark:hover:text-slate-200'"
      >
        <M3Icon name="search" :size="16" />
        <span>规则检测工具</span>
      </button>
      <button
        @click="activeTab = 'config'"
        class="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2"
        :class="activeTab === 'config' ? 'border-primary text-primary' : 'border-transparent text-slate-500 hover:text-slate-800 dark:hover:text-slate-200'"
      >
        <M3Icon name="settings" :size="16" />
        <span>拦截策略</span>
      </button>
    </div>

    <!-- TAB 1: 订阅规则源列表 -->
    <div v-if="activeTab === 'lists'" class="space-y-4">
      <div class="flex items-center justify-between">
        <span class="text-xs text-slate-500 dark:text-slate-400">支持 HTTP(S) 公网规则源与本地文本规则库</span>
        <div class="flex items-center gap-3">
          <md-outlined-button @click="refreshList()" :disabled="refreshing">
            <M3Icon name="refresh" :size="16" slot="icon" class="mr-1" />
            <span>{{ refreshing ? '正在全量拉取...' : '全量刷新' }}</span>
          </md-outlined-button>
          <md-filled-button @click="isAddModalOpen = true">
            <M3Icon name="add" :size="16" slot="icon" class="mr-1" />
            <span>添加订阅</span>
          </md-filled-button>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          v-for="l in lists"
          :key="l.id"
          class="p-5 rounded-2xl bg-surface-container-low border border-slate-200/60 dark:border-slate-800 shadow-sm flex flex-col justify-between gap-4"
        >
          <div>
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 min-w-0">
                <span class="font-bold text-slate-800 dark:text-slate-100 truncate text-sm">{{ l.name }}</span>
                <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-primary/10 text-primary shrink-0">
                  {{ l.rulesCount.toLocaleString() }} 条规则
                </span>
              </div>
              <md-switch :selected="l.enabled" @change="toggleList(l)"></md-switch>
            </div>
            <p class="text-xs text-slate-400 font-mono mt-2 truncate select-all" :title="l.url">{{ l.url }}</p>
          </div>

          <div class="flex items-center justify-between pt-3 border-t border-slate-100 dark:border-slate-800/80 text-[11px] text-slate-400">
            <span>最后同步: {{ formatTime(l.lastUpdated) }}</span>
            <div class="flex items-center gap-2">
              <button @click="refreshList(l.id)" class="p-1.5 rounded-lg hover:bg-slate-200/50 dark:hover:bg-slate-800 text-slate-500" title="重新拉取">
                <M3Icon name="refresh" :size="14" />
              </button>
              <button @click="deleteList(l.id)" class="p-1.5 rounded-lg hover:bg-error/10 text-error" title="移除此源">
                <M3Icon name="delete" :size="14" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- TAB 2: 自定义规则编辑器 -->
    <div v-if="activeTab === 'custom'" class="space-y-4">
      <div class="p-4 rounded-2xl bg-surface-container-low border border-slate-200/60 dark:border-slate-800 text-xs text-slate-600 dark:text-slate-300 space-y-1">
        <div class="font-bold text-slate-800 dark:text-slate-100 mb-1 flex items-center gap-2">
          <M3Icon name="info" :size="14" class="text-primary" />
          <span>规则语法快捷参考</span>
        </div>
        <div>• <code class="bg-slate-200/60 dark:bg-slate-800 px-1 py-0.5 rounded text-primary font-mono">||example.com^</code> 拦截该域名及其所有子域名</div>
        <div>• <code class="bg-slate-200/60 dark:bg-slate-800 px-1 py-0.5 rounded text-primary font-mono">@@||safe.com^</code> 白名单例外放行 (优先于拦截规则)</div>
        <div>• <code class="bg-slate-200/60 dark:bg-slate-800 px-1 py-0.5 rounded text-primary font-mono">0.0.0.0 bad.com</code> 兼容标准 Hosts 阻断条目</div>
        <div>• <code class="bg-slate-200/60 dark:bg-slate-800 px-1 py-0.5 rounded text-primary font-mono">||urgent.com^$important</code> 最高权重重要阻断，覆盖常规白名单</div>
      </div>

      <div class="rounded-2xl border border-slate-200/80 dark:border-slate-800 bg-surface-container-lowest p-2 focus-within:ring-2 focus-within:ring-primary/40">
        <textarea
          v-model="customRulesText"
          rows="14"
          placeholder="在此输入自定义过滤规则，每行一条..."
          class="w-full bg-transparent border-0 resize-y p-2 text-xs font-mono text-slate-800 dark:text-slate-200 focus:outline-none"
        ></textarea>
      </div>

      <div class="flex items-center justify-end gap-3">
        <md-filled-button @click="saveCustomRules" :disabled="saving">
          <M3Icon name="check" :size="16" slot="icon" class="mr-1" />
          <span>{{ saving ? '保存中...' : '保存自定义规则' }}</span>
        </md-filled-button>
      </div>
    </div>

    <!-- TAB 3: 域名规则检测工具 -->
    <div v-if="activeTab === 'test'" class="space-y-4">
      <div class="p-6 rounded-2xl bg-surface-container-low border border-slate-200/60 dark:border-slate-800 space-y-4">
        <div>
          <h3 class="text-base font-bold text-slate-800 dark:text-slate-100">域名检测与命中分析</h3>
          <p class="text-xs text-slate-400 mt-1">输入任意域名，即时测试其当前在 Trie 树和规则集中的匹配结果与处理动作</p>
        </div>

        <div class="flex flex-col md:flex-row gap-3">
          <input
            v-model="testDomain"
            placeholder="例如: pagead2.googlesyndication.com"
            @keyup.enter="runDomainTest"
            class="flex-1 px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-800 bg-surface text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
          />
          <select
            v-model="testQType"
            class="px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-800 bg-surface text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
          >
            <option value="A">Type A (IPv4)</option>
            <option value="AAAA">Type AAAA (IPv6)</option>
            <option value="ANY">Type ANY</option>
          </select>
          <md-filled-button @click="runDomainTest" :disabled="testing || !testDomain.trim()">
            <M3Icon name="search" :size="16" slot="icon" class="mr-1" />
            <span>{{ testing ? '检测中...' : '立即测试' }}</span>
          </md-filled-button>
        </div>

        <div v-if="testResult" class="p-5 rounded-xl border text-sm animate-fade-in" :class="testResult.blocked ? 'bg-error/5 border-error/20' : testResult.action === 'allow' ? 'bg-primary/5 border-primary/20' : 'bg-slate-100 dark:bg-slate-900 border-slate-200 dark:border-slate-800'">
          <div class="flex items-center gap-3">
            <span
              class="px-2.5 py-1 rounded-full text-xs font-bold uppercase"
              :class="testResult.blocked ? 'bg-error text-white' : testResult.action === 'allow' ? 'bg-primary text-white' : 'bg-slate-500 text-white'"
            >
              {{ testResult.blocked ? '已阻断 (BLOCKED)' : testResult.action === 'allow' ? '白名单放行 (ALLOWED)' : '正常通过 (PASS)' }}
            </span>
            <span class="font-mono font-bold text-slate-800 dark:text-slate-100">{{ testDomain }}</span>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-3 gap-3 mt-4 text-xs">
            <div>
              <span class="text-slate-400">命中规则: </span>
              <span class="font-mono text-slate-700 dark:text-slate-200">{{ testResult.matchedRule || '无' }}</span>
            </div>
            <div>
              <span class="text-slate-400">规则来源: </span>
              <span class="font-medium text-slate-700 dark:text-slate-200">{{ testResult.listName || '无' }}</span>
            </div>
            <div>
              <span class="text-slate-400">判定原因: </span>
              <span class="font-medium text-slate-700 dark:text-slate-200">{{ testResult.reason || '未命中规则' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- TAB 4: 策略配置 -->
    <div v-if="activeTab === 'config'" class="space-y-4 max-w-2xl">
      <div class="p-6 rounded-2xl bg-surface-container-low border border-slate-200/60 dark:border-slate-800 space-y-5">
        <div>
          <h3 class="text-base font-bold text-slate-800 dark:text-slate-100">阻断响应策略配置</h3>
          <p class="text-xs text-slate-400 mt-1">定制当域名被命中阻断时向客户端交付的 DNS 应答行为</p>
        </div>

        <div class="space-y-3 text-sm">
          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-slate-100 dark:hover:bg-slate-800/60 transition-colors">
            <input type="radio" v-model="config.blockMode" value="null_ip" class="text-primary" />
            <div>
              <div class="font-medium text-slate-800 dark:text-slate-100">空 IP 应答 (Null IP / 推荐)</div>
              <div class="text-xs text-slate-400">返回 0.0.0.0 (A) 或 :: (AAAA)，快速阻断且不引起客户端持续重试</div>
            </div>
          </label>

          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-slate-100 dark:hover:bg-slate-800/60 transition-colors">
            <input type="radio" v-model="config.blockMode" value="nxdomain" class="text-primary" />
            <div>
              <div class="font-medium text-slate-800 dark:text-slate-100">域名不存在 (NXDOMAIN)</div>
              <div class="text-xs text-slate-400">响应 RcodeNameError，宣告域名在权威服务中不存在</div>
            </div>
          </label>

          <label class="flex items-center gap-3 cursor-pointer p-3 rounded-xl hover:bg-slate-100 dark:hover:bg-slate-800/60 transition-colors">
            <input type="radio" v-model="config.blockMode" value="refused" class="text-primary" />
            <div>
              <div class="font-medium text-slate-800 dark:text-slate-100">拒绝访问 (REFUSED)</div>
              <div class="text-xs text-slate-400">响应 RcodeRefused，告知请求被 DNS 策略拒绝</div>
            </div>
          </label>
        </div>

        <div class="pt-4 border-t border-slate-200/60 dark:border-slate-800 flex justify-end">
          <md-filled-button @click="saveConfig" :disabled="saving">
            <M3Icon name="check" :size="16" slot="icon" class="mr-1" />
            <span>{{ saving ? '保存中...' : '保存策略' }}</span>
          </md-filled-button>
        </div>
      </div>
    </div>

    <!-- 添加订阅弹窗 Modal -->
    <div v-if="isAddModalOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm animate-fade-in">
      <div class="w-full max-w-md p-6 rounded-3xl bg-surface-container-high border border-slate-200 dark:border-slate-800 shadow-2xl space-y-4">
        <h3 class="text-lg font-bold text-slate-800 dark:text-slate-100">添加规则订阅源</h3>
        <p class="text-xs text-slate-500">输入规则列表源的名称与可访问的 URL 地址</p>

        <div class="space-y-3">
          <div>
            <label class="text-xs text-slate-400 block mb-1">规则源名称</label>
            <input
              v-model="newListName"
              placeholder="例如: EasyList China"
              class="w-full px-3 py-2 rounded-xl border border-slate-200 dark:border-slate-800 bg-surface text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            />
          </div>
          <div>
            <label class="text-xs text-slate-400 block mb-1">规则源 URL / 路径</label>
            <input
              v-model="newListURL"
              placeholder="https://... 或本地文件路径"
              class="w-full px-3 py-2 rounded-xl border border-slate-200 dark:border-slate-800 bg-surface text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            />
          </div>
        </div>

        <div class="flex items-center justify-end gap-3 pt-2">
          <md-text-button @click="isAddModalOpen = false">取消</md-text-button>
          <md-filled-button @click="handleAddList" :disabled="saving || !newListURL.trim()">添加并拉取</md-filled-button>
        </div>
      </div>
    </div>
  </div>
</template>
