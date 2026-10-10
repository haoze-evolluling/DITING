<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { ipc } from '../api/ipc';
import type { LANStatusResponse } from '../api/types';
import M3Icon from './M3Icon.vue';
import StatusBadge from './StatusBadge.vue';
import ToastBanner from './ToastBanner.vue';
import { revertSwitch } from '../utils/switch';
import { useCopyFeedback } from '../composables/useCopyFeedback';

const loading = ref(false);
const toggling = ref(false);
const togglingFw = ref(false);
const lanStatus = ref<LANStatusResponse | null>(null);
const errorMessage = ref('');
const successMessage = ref('');
const { copiedValue, copy, isCopied } = useCopyFeedback();

const allowLAN = computed(() => !!lanStatus.value?.allowLAN);
const lanAddresses = computed(() => lanStatus.value?.lanAddresses || []);
const firewallAllowed = computed(() => !!lanStatus.value?.firewallAllowed);

function flashSuccess(message: string, durationMs = 4000) {
  successMessage.value = message;
  setTimeout(() => {
    successMessage.value = '';
  }, durationMs);
}

async function loadData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    lanStatus.value = await ipc.getLANStatus();
  } catch (err: any) {
    errorMessage.value = err.message || '加载局域网 DNS 服务状态失败';
  } finally {
    loading.value = false;
  }
}

async function handleToggleLAN(e: Event) {
  const enable = Boolean((e.target as any).selected ?? (e.target as any).checked);
  toggling.value = true;
  errorMessage.value = '';
  successMessage.value = '';

  try {
    await ipc.configureLAN({
      allowLAN: enable,
      configureFirewall: true, // 保持防火墙放行规则与局域网服务状态一致（开启时放行，关闭时清除）
    });
    flashSuccess(
      enable
        ? '局域网 DNS 服务器已成功开启！局域网内其他设备现可填入本机 IP 使用。'
        : '已关闭局域网 DNS 服务，恢复为仅本机 (127.0.0.1) 监听。'
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
    const msg = await ipc.configureFirewall(nextState);
    flashSuccess(msg || (nextState ? '已放行防火墙 53 端口' : '已关闭防火墙放行'), 3000);
    await loadData();
  } catch (err: any) {
    errorMessage.value = `配置防火墙失败: ${err.message}`;
  } finally {
    togglingFw.value = false;
  }
}

onMounted(() => {
  loadData();
});
</script>

<template>
  <div class="rounded-2xl border border-surface-border bg-surface-card p-6 shadow-xs space-y-6 transition-colors">
    <!-- 头部与主控制开关 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-surface-border">
      <div class="space-y-1">
        <div class="flex items-center gap-2.5">
          <M3Icon name="router" :size="22" class="text-brand-primary" />
          <h3 class="text-lg font-bold text-text-main">
            局域网 DNS 服务器 (AdGuard Home 模式)
          </h3>
          <StatusBadge
            :status="allowLAN ? 'active' : 'inactive'"
            :text="allowLAN ? '全网监听中 (0.0.0.0)' : '仅本机模式'"
          />
        </div>
        <p class="text-xs text-text-sub max-w-2xl">
          使本机作为局域网内的 DNS 服务器运行。局域网内其他设备（路由器、手机、平板、NAS）将 DNS 设置为本机的局域网 IP，即可统一通过谛听进行 DNS 解析、智能加速与过滤拦截。
        </p>
      </div>

      <div class="flex items-center gap-3 shrink-0">
        <span class="text-xs font-semibold text-text-sub">
          {{ allowLAN ? '服务已激活' : '已关闭' }}
        </span>
        <md-switch
          :selected="allowLAN"
          :disabled="toggling || loading"
          @change="handleToggleLAN"
        />
      </div>
    </div>

    <!-- 消息提示栏 -->
    <ToastBanner v-if="successMessage" :message="successMessage" type="success" compact />
    <ToastBanner v-if="errorMessage" :message="errorMessage" type="error" compact dismissible @dismiss="errorMessage = ''" />

    <!-- 核心卡片网格：IP 地址展示与防火墙状态 -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-5">
      <!-- 局域网 IP 地址卡片 (占据 2 列) -->
      <div class="lg:col-span-2 p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <M3Icon name="dns" :size="18" class="text-brand-primary" />
            <span class="text-sm font-bold text-text-main">本机局域网 DNS 服务器地址</span>
          </div>
          <button
            type="button"
            @click="loadData"
            :disabled="loading"
            class="app-btn-secondary app-btn-compact text-[11px]"
            title="刷新本机 IP"
          >
            <M3Icon name="refresh" :size="14" :class="loading ? 'animate-spin' : ''" />
            <span>刷新</span>
          </button>
        </div>

        <p class="text-xs text-text-sub">
          在其他设备的网络设置中填入以下 IP 地址作为首选 DNS 服务器：
        </p>

        <!-- IP 地址列表 -->
        <div v-if="lanAddresses.length > 0" class="space-y-2 pt-1">
          <div
            v-for="ip in lanAddresses"
            :key="ip"
            class="flex items-center justify-between p-2.5 rounded-lg bg-surface-card border border-surface-border hover:border-brand-primary/40 transition-colors"
          >
            <div class="flex items-center gap-2.5 min-w-0">
              <span
                class="px-1.5 py-0.5 rounded text-[10px] font-bold shrink-0"
                :class="ip.includes(':') ? 'bg-purple-500/10 text-purple-600 dark:text-purple-400' : 'bg-brand-primary/10 text-brand-primary'"
              >
                {{ ip.includes(':') ? 'IPv6' : 'IPv4 首选' }}
              </span>
              <span class="font-mono text-xs font-semibold text-text-main truncate select-all">
                {{ ip }}
              </span>
            </div>

            <button
              type="button"
              @click="copy(ip)"
              class="app-btn-secondary app-btn-compact text-[11px] shrink-0"
            >
              <M3Icon :name="isCopied(ip) ? 'check' : 'content_copy'" :size="13" />
              <span>{{ isCopied(ip) ? '已复制' : '复制' }}</span>
            </button>
          </div>
        </div>
        <div v-else class="text-xs text-text-sub italic py-2">
          未检测到物理活动网卡 IP，请确认本机已连接 Wi-Fi 或以太网局域网。
        </div>
      </div>

      <!-- Windows 防火墙状态卡片 (占据 1 列) -->
      <div class="p-4 rounded-xl border border-surface-border-sub bg-surface-card-sub space-y-3 flex flex-col justify-between">
        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-sm font-bold text-text-main flex items-center gap-1.5">
              <M3Icon name="shield" :size="16" class="text-brand-primary" />
              防火墙放行状态
            </span>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-bold"
              :class="firewallAllowed ? 'bg-status-success-bg text-status-success' : 'bg-status-warning-bg text-status-warning'"
            >
              {{ firewallAllowed ? '已放行 53 端口' : '未放行' }}
            </span>
          </div>

          <p class="text-xs text-text-sub leading-relaxed">
            局域网其他设备需通过 UDP/TCP 53 端口访问本机。若 Windows Defender 防火墙拦截入站请求，外部设备将无法完成解析。
          </p>
        </div>

        <button
          type="button"
          @click="handleToggleFirewall"
          :disabled="togglingFw"
          class="w-full text-xs justify-center"
          :class="firewallAllowed ? 'app-btn-secondary' : 'app-btn-primary'"
        >
          <M3Icon v-if="togglingFw" name="sync" :size="14" class="animate-spin" />
          <M3Icon v-else :name="firewallAllowed ? 'block' : 'verified_user'" :size="14" />
          <span>{{ firewallAllowed ? '移除防火墙放行' : '一键放行入站 53 端口' }}</span>
        </button>
      </div>
    </div>

    <!-- 局域网设备接入指引 (AdGuard Home 经典指南折叠体系) -->
    <div class="rounded-xl border border-surface-border-sub bg-surface-card-sub p-4 space-y-3">
      <div class="flex items-center gap-2">
        <M3Icon name="help_outline" :size="18" class="text-brand-primary" />
        <h4 class="text-xs font-bold text-text-main uppercase tracking-wider">
          局域网设备接入与配置指引
        </h4>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
        <!-- 方案 1：路由器全局配置 -->
        <div class="p-3 rounded-lg bg-surface-card border border-surface-border space-y-1.5">
          <div class="font-bold text-text-main flex items-center gap-1.5 text-brand-primary">
            <M3Icon name="wifi" :size="16" />
            <span>方案 A：路由器全局配置 (强烈推荐)</span>
          </div>
          <p class="text-text-sub leading-relaxed">
            登录家用路由器后台 (通常为 192.168.1.1 或 192.168.0.1)，进入「LAN 口设置」或「DHCP 服务器」，将「主 DNS 服务器」修改为本机的局域网 IP (例如 <span class="font-mono text-brand-primary select-all">{{ lanAddresses[0] || '192.168.x.x' }}</span>)。保存后全屋所有设备自动生效！
          </p>
        </div>

        <!-- 方案 2：移动设备与电脑独立配置 -->
        <div class="p-3 rounded-lg bg-surface-card border border-surface-border space-y-1.5">
          <div class="font-bold text-text-main flex items-center gap-1.5 text-brand-primary">
            <M3Icon name="devices" :size="16" />
            <span>方案 B：手机 / 平板 / 电脑单机配置</span>
          </div>
          <p class="text-text-sub leading-relaxed">
            在手机或电脑的 Wi-Fi 设置中，将 IP 设置从 DHCP 改为「静态/手动」，并将 DNS 服务器地址修改为本机的局域网 IP。适合特定设备单独体验谛听的加速与拦截效果。
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
