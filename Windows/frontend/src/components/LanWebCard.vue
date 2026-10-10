<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue';
import QRCode from 'qrcode';
import { ipc } from '../api/ipc';
import type { WebStatusResponse } from '../api/types';
import M3Icon from './M3Icon.vue';
import StatusBadge from './StatusBadge.vue';
import ToastBanner from './ToastBanner.vue';
import LoginModal from './LoginModal.vue';
import { revertSwitch } from '../utils/switch';
import { useCopyFeedback } from '../composables/useCopyFeedback';

const loading = ref(false);
const toggling = ref(false);
const togglingFw = ref(false);
const webStatus = ref<WebStatusResponse | null>(null);
const errorMessage = ref('');
const successMessage = ref('');
const showPasswordModal = ref(false);
const selectedQrUrl = ref<string>('');
const qrDataUrl = ref<string>('');
const isEditingPort = ref(false);
const customPort = ref('15353');
const { copy, isCopied } = useCopyFeedback();

const isEnabled = computed(() => !!webStatus.value?.enabled);
const webUrls = computed(() => webStatus.value?.webUrls || []);
const firewallAllowed = computed(() => !!webStatus.value?.firewallAllowed);
const adminUser = computed(() => webStatus.value?.username || 'admin');
const isInitialized = computed(() => !!webStatus.value?.initialized);

function flashSuccess(message: string, durationMs = 3000) {
  successMessage.value = message;
  setTimeout(() => {
    successMessage.value = '';
  }, durationMs);
}

async function loadData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const data = await ipc.getWebStatus();
    webStatus.value = data;
    customPort.value = String(data.port || 15353);
    if (data.webUrls && data.webUrls.length > 0) {
      selectedQrUrl.value = data.webUrls[0];
      generateQR(data.webUrls[0]);
    }
  } catch (err: any) {
    errorMessage.value = err.message || '加载局域网 Web 状态失败';
  } finally {
    loading.value = false;
  }
}

async function generateQR(url: string) {
  if (!url) {
    qrDataUrl.value = '';
    return;
  }
  try {
    qrDataUrl.value = await QRCode.toDataURL(url, {
      width: 160,
      margin: 1,
      color: {
        dark: '#1A1A1C',
        light: '#FFFFFF',
      },
    });
  } catch (e) {
    console.warn('生成二维码失败:', e);
  }
}

watch(selectedQrUrl, (newUrl) => {
  generateQR(newUrl);
});

async function handleToggleWeb(e: Event) {
  const enable = Boolean((e.target as any).selected ?? (e.target as any).checked);
  toggling.value = true;
  errorMessage.value = '';
  successMessage.value = '';

  const portNum = parseInt(customPort.value, 10) || 15353;

  try {
    await ipc.configureWeb({
      enabled: enable,
      port: portNum,
      configureFirewall: true,
    });
    flashSuccess(
      enable
        ? '局域网 Web 远程管理已成功开启！局域网其他设备现可通过浏览器访问。'
        : '已关闭局域网 Web 管理，服务恢复为仅限本地 (127.0.0.1) 通信。',
      4000
    );
    await loadData();
  } catch (err: any) {
    errorMessage.value = `操作失败: ${err.message}`;
    revertSwitch(e, !enable);
  } finally {
    toggling.value = false;
  }
}

async function handleToggleFirewall() {
  togglingFw.value = true;
  errorMessage.value = '';
  try {
    const nextState = !firewallAllowed.value;
    const msg = await ipc.configureWebFirewall(nextState);
    flashSuccess(msg || (nextState ? '已放行防火墙 Web 端口' : '已关闭防火墙放行'));
    await loadData();
  } catch (err: any) {
    errorMessage.value = `配置防火墙失败: ${err.message}`;
  } finally {
    togglingFw.value = false;
  }
}

async function handleSavePort() {
  const portNum = parseInt(customPort.value, 10);
  if (!portNum || portNum < 1 || portNum > 65535) {
    errorMessage.value = '请输入有效的端口号 (1-65535)';
    return;
  }
  isEditingPort.value = false;
  try {
    await ipc.configureWeb({
      enabled: isEnabled.value,
      port: portNum,
      configureFirewall: true,
    });
    flashSuccess(`Web 端口已成功更新为 ${portNum}`);
    await loadData();
  } catch (err: any) {
    errorMessage.value = `保存端口失败: ${err.message}`;
  }
}

function openInBrowser(url: string) {
  window.open(url, '_blank');
}

onMounted(() => {
  loadData();
});
</script>

<template>
  <div class="rounded-md border border-surface-border bg-surface-card p-5 space-y-5 transition-colors">
    <!-- 头部标题与总开关 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div class="space-y-1">
        <div class="flex items-center gap-2.5">
          <div class="w-8 h-8 rounded-md bg-brand-container/60 flex items-center justify-center shrink-0">
            <M3Icon name="web" :size="20" class="text-text-main" />
          </div>
          <h3 class="section-title flex items-center gap-2">
            局域网 Web 远程管理控制台
          </h3>
          <StatusBadge
            :status="isEnabled ? 'active' : 'inactive'"
            :text="isEnabled ? '已对外开放' : '仅本地访问'"
            :pulse="isEnabled"
            size="sm"
          />
        </div>
        <p class="text-xs text-text-sub leading-relaxed max-w-2xl">
          开启后，局域网内的手机、平板或其他电脑可通过浏览器访问完整控制台进行远程管理，与桌面客户端共享核心数据与配置同步。
        </p>
      </div>

      <!-- 右侧启闭开关 -->
      <div class="flex items-center gap-3 self-end sm:self-center shrink-0">
        <span class="text-xs font-semibold text-text-main">
          {{ isEnabled ? '远程管理已开启' : '已关闭' }}
        </span>
        <md-switch
          :selected="isEnabled"
          :disabled="loading || toggling"
          @change="handleToggleWeb"
        />
      </div>
    </div>

    <!-- 成功与错误反馈横幅 -->
    <ToastBanner v-if="successMessage" :message="successMessage" type="success" compact dismissible @dismiss="successMessage = ''" />
    <ToastBanner v-if="errorMessage" :message="errorMessage" type="error" compact dismissible @dismiss="errorMessage = ''" />

    <!-- 展开详情面板 (当开启 Web 远程管理时) -->
    <div v-if="isEnabled" class="space-y-5 pt-2 border-t border-surface-border">
      <!-- 1. 局域网管理地址与手机扫码 -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-5">
        <!-- 左侧: 局域网访问地址列表 -->
        <div class="lg:col-span-2 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-xs font-bold text-text-main flex items-center gap-1.5">
              <M3Icon name="link" :size="16" class="text-text-main" />
              局域网 Web 访问地址 (浏览器直接打开)
            </span>
            <span class="text-[11px] text-text-sub font-mono">
              端口: {{ webStatus?.port || 15353 }}
            </span>
          </div>

          <div v-if="webUrls.length === 0" class="p-4 rounded-md bg-surface-card-sub text-center text-xs text-text-sub">
            未探测到可用的局域网网卡 IPv4 地址
          </div>
          <div v-else class="space-y-2">
            <div
              v-for="url in webUrls"
              :key="url"
              class="flex flex-wrap items-center justify-between gap-3 p-3 rounded-md bg-surface-card-sub border border-surface-border hover:border-accent-seal/40 transition-all"
            >
              <div class="flex items-center gap-2.5 min-w-0">
                <span class="w-2 h-2 rounded-full bg-status-success shrink-0"></span>
                <span class="font-mono text-xs font-semibold text-text-main truncate select-all">
                  {{ url }}
                </span>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  @click="copy(url)"
                  class="app-btn-secondary app-btn-compact"
                  :title="isCopied(url) ? '已复制！' : '复制网址'"
                >
                  <M3Icon :name="isCopied(url) ? 'check' : 'content_copy'" :size="14" />
                  <span>{{ isCopied(url) ? '已复制' : '复制' }}</span>
                </button>
                <button
                  type="button"
                  @click="openInBrowser(url)"
                  class="app-btn-primary app-btn-compact"
                  title="在默认浏览器中打开"
                >
                  <M3Icon name="open_in_new" :size="14" />
                  <span>打开</span>
                </button>
              </div>
            </div>
          </div>

          <!-- 安全凭据与密码修改 -->
          <div class="flex items-center justify-between p-3.5 rounded-md bg-brand-container/20 border border-accent-seal/20 mt-3">
            <div class="flex items-center gap-2.5">
              <M3Icon name="key" :size="18" class="text-text-main" />
              <div>
                <span class="text-xs font-bold text-text-main">
                  管理员账号: <span class="font-mono text-text-main font-semibold">{{ adminUser }}</span>
                </span>
                <p class="text-[11px] text-text-sub">
                  {{ isInitialized ? '密码保护已启用，局域网设备需输入密码登录' : '尚未设置初始密码，首次访问将进入设置向导' }}
                </p>
              </div>
            </div>
            <button
              type="button"
              @click="showPasswordModal = true"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon name="lock_reset" :size="14" />
              <span>{{ isInitialized ? '修改管理员密码' : '设置初始密码' }}</span>
            </button>
          </div>
        </div>

        <!-- 右侧: 手机快速扫码直达卡片 -->
        <div class="rounded-md bg-surface-card-sub border border-surface-border p-4 flex flex-col items-center justify-center text-center gap-2.5">
          <span class="text-xs font-bold text-text-main flex items-center gap-1.5">
            <M3Icon name="qr_code" :size="16" class="text-text-main" />
            手机扫码即刻管理
          </span>
          <div class="p-2 rounded-md bg-white border border-surface-border">
            <img
              v-if="qrDataUrl"
              :src="qrDataUrl"
              alt="手机扫码二维码"
              class="w-32 h-32 block"
            />
            <div v-else class="w-32 h-32 flex items-center justify-center text-text-muted text-xs">
              加载二维码中...
            </div>
          </div>
          <p class="text-[11px] text-text-sub leading-tight">
            确保手机连接至同一 Wi-Fi<br />系统相机扫码直达控制台
          </p>
        </div>
      </div>

      <!-- 2. 防火墙放行状态与端口调整 -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-surface-border/60">
        <!-- 防火墙规则卡片 -->
        <div class="flex items-center justify-between p-3.5 rounded-md bg-surface-card-sub border border-surface-border">
          <div class="space-y-0.5">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold text-text-main">Windows 防火墙规则</span>
              <StatusBadge
                :status="firewallAllowed ? 'active' : 'warning'"
                :text="firewallAllowed ? '已放行' : '未放行'"
                size="sm"
              />
            </div>
            <p class="text-[11px] text-text-sub">
              放行 TCP {{ webStatus?.port || 15353 }} 端口允许局域网设备连入
            </p>
          </div>
          <button
            type="button"
            @click="handleToggleFirewall"
            :disabled="togglingFw"
            class="app-btn-secondary app-btn-compact"
          >
            <M3Icon :name="firewallAllowed ? 'block' : 'shield'" :size="14" />
            <span>{{ firewallAllowed ? '清除放行' : '一键放行' }}</span>
          </button>
        </div>

        <!-- 端口修改 -->
        <div class="flex items-center justify-between p-3.5 rounded-md bg-surface-card-sub border border-surface-border">
          <div class="space-y-0.5">
            <span class="text-xs font-bold text-text-main">远程管理通信端口</span>
            <p class="text-[11px] text-text-sub font-mono">
              当前: {{ webStatus?.port || 15353 }} (TCP)
            </p>
          </div>
          <div v-if="!isEditingPort" class="flex items-center gap-2">
            <button
              type="button"
              @click="isEditingPort = true"
              class="app-btn-secondary app-btn-compact"
            >
              <M3Icon name="tune" :size="14" />
              <span>修改端口</span>
            </button>
          </div>
          <div v-else class="flex items-center gap-2">
            <input
              type="number"
              v-model="customPort"
              class="w-20 px-2 py-1 text-xs font-mono rounded-md border border-surface-border bg-surface-card text-text-main focus:outline-none focus:border-accent-seal placeholder:text-text-muted"
            />
            <button
              type="button"
              @click="handleSavePort"
              class="app-btn-primary app-btn-compact"
            >
              保存
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- 弹窗：设置 / 修改管理员密码 -->
    <LoginModal
      :open="showPasswordModal"
      :mode="isInitialized ? 'change_password' : 'setup'"
      @close="showPasswordModal = false"
      @success="loadData"
    />
  </div>
</template>
