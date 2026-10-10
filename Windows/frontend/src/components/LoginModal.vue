<script setup lang="ts">
import { ref, watch, onUnmounted } from 'vue';
import { ipc } from '../api/ipc';
import M3Icon from './M3Icon.vue';
import AppModal from './AppModal.vue';

const props = withDefaults(
  defineProps<{
    open: boolean;
    mode?: 'login' | 'setup' | 'change_password';
    forceModal?: boolean;
  }>(),
  {
    open: false,
    mode: 'login',
    forceModal: false,
  }
);

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'success'): void;
}>();

const currentMode = ref<'login' | 'setup' | 'change_password'>(props.mode);
const username = ref('admin');
const password = ref('');
const confirmPassword = ref('');
const oldPassword = ref('');
const loading = ref(false);
const errorMsg = ref('');
const successMsg = ref('');
const lockoutSeconds = ref(0);
let lockoutTimer: any = null;

watch(
  () => props.open,
  (val) => {
    if (val) {
      currentMode.value = props.mode;
      password.value = '';
      confirmPassword.value = '';
      oldPassword.value = '';
      errorMsg.value = '';
      successMsg.value = '';
      checkInitialAuth();
    }
  }
);

watch(
  () => props.mode,
  (val) => {
    currentMode.value = val;
  }
);

async function checkInitialAuth() {
  try {
    const status = await ipc.getAuthStatus();
    if (!status.initialized && currentMode.value === 'login') {
      currentMode.value = 'setup';
    }
    if (status.username) {
      username.value = status.username;
    }
    if (status.locked && status.lockoutRemainingSec > 0) {
      startLockoutCountdown(status.lockoutRemainingSec);
    }
  } catch {}
}

function startLockoutCountdown(seconds: number) {
  lockoutSeconds.value = seconds;
  if (lockoutTimer) clearInterval(lockoutTimer);
  lockoutTimer = setInterval(() => {
    lockoutSeconds.value--;
    if (lockoutSeconds.value <= 0) {
      clearInterval(lockoutTimer);
      lockoutTimer = null;
      errorMsg.value = '';
    }
  }, 1000);
}

onUnmounted(() => {
  if (lockoutTimer) clearInterval(lockoutTimer);
});

async function handleSubmit() {
  errorMsg.value = '';
  successMsg.value = '';

  if (currentMode.value === 'setup') {
    if (!username.value.trim()) {
      errorMsg.value = '管理员用户名不能为空';
      return;
    }
    if (password.value.length < 4) {
      errorMsg.value = '密码长度至少为 4 位字符';
      return;
    }
    if (password.value !== confirmPassword.value) {
      errorMsg.value = '两次输入的密码不一致';
      return;
    }

    loading.value = true;
    try {
      await ipc.setupAuth({
        username: username.value.trim(),
        password: password.value,
      });
      // 初始化成功后自动执行登录
      await ipc.login({
        username: username.value.trim(),
        password: password.value,
      });
      successMsg.value = '管理员账号初始化成功并已自动登录！';
      setTimeout(() => {
        emit('success');
        emit('close');
      }, 1000);
    } catch (err: any) {
      errorMsg.value = err.message || '初始化管理员账号失败';
    } finally {
      loading.value = false;
    }
    return;
  }

  if (currentMode.value === 'login') {
    if (!username.value.trim()) {
      errorMsg.value = '请输入用户名';
      return;
    }
    if (!password.value) {
      errorMsg.value = '请输入密码';
      return;
    }

    loading.value = true;
    try {
      await ipc.login({
        username: username.value.trim(),
        password: password.value,
      });
      successMsg.value = '登录成功，正在进入控制台...';
      setTimeout(() => {
        emit('success');
        emit('close');
      }, 800);
    } catch (err: any) {
      errorMsg.value = err.message || '登录失败，请检查账号密码';
      if (err.message && err.message.includes('锁定')) {
        startLockoutCountdown(300);
      }
    } finally {
      loading.value = false;
    }
    return;
  }

  if (currentMode.value === 'change_password') {
    if (password.value.length < 4) {
      errorMsg.value = '新密码长度至少为 4 位字符';
      return;
    }
    if (password.value !== confirmPassword.value) {
      errorMsg.value = '两次输入的新密码不一致';
      return;
    }

    loading.value = true;
    try {
      await ipc.changePassword({
        username: username.value.trim(),
        oldPassword: oldPassword.value,
        newPassword: password.value,
      });
      successMsg.value = '管理员密码修改成功！请使用新密码重新登录。';
      setTimeout(() => {
        emit('success');
        emit('close');
      }, 1500);
    } catch (err: any) {
      errorMsg.value = err.message || '修改密码失败';
    } finally {
      loading.value = false;
    }
  }
}

function handleClose() {
  if (props.forceModal) return;
  emit('close');
}
</script>

<template>
  <AppModal
    :open="open"
    @close="handleClose"
    max-width="max-w-md"
  >
    <template #headline>
      <div class="flex items-center gap-3 w-full">
        <div class="w-10 h-10 rounded-md bg-brand-container flex items-center justify-center shrink-0 ">
          <M3Icon
            :name="currentMode === 'setup' ? 'key' : (currentMode === 'change_password' ? 'lock_reset' : 'verified_user')"
            :size="22"
            class="text-text-main"
          />
        </div>
        <div>
          <h3 class="section-title">
            {{ currentMode === 'setup' ? '初始化管理员账号' : (currentMode === 'change_password' ? '修改管理员密码' : '登录谛听 Web 管理控制台') }}
          </h3>
          <p class="text-xs text-text-sub mt-0.5">
            {{ currentMode === 'setup' ? '设置初始账号与密码，守护局域网远程管理安全' : (currentMode === 'change_password' ? '更新凭据后所有外部会话将自动失效' : '请输入管理员凭据以远程管理谛听 DNS') }}
          </p>
        </div>
      </div>
    </template>

    <div class="space-y-4 py-1">
      <!-- 提示横幅 -->
      <div v-if="errorMsg" class="p-3 rounded-md bg-status-error-bg border border-status-error/30 text-status-error text-xs flex items-center gap-2">
        <M3Icon name="error" :size="16" class="shrink-0" />
        <span>{{ errorMsg }}</span>
      </div>

      <div v-if="successMsg" class="p-3 rounded-md bg-status-success-bg border border-status-success/30 text-status-success text-xs flex items-center gap-2">
        <M3Icon name="check_circle" :size="16" class="shrink-0" />
        <span>{{ successMsg }}</span>
      </div>

      <div v-if="lockoutSeconds > 0" class="p-3 rounded-md bg-status-warning-bg border border-status-warning/30 text-status-warning text-xs flex items-center gap-2">
        <M3Icon name="alarm" :size="16" class="shrink-0" />
        <span>安全保护锁定中，请在 {{ lockoutSeconds }} 秒后再试</span>
      </div>

      <!-- 表单输入区 -->
      <div class="space-y-3.5">
        <div>
          <md-outlined-text-field
            label="管理员账号"
            :value="username"
            @input="username = ($event.target as any).value"
            :disabled="loading || lockoutSeconds > 0"
            class="w-full"
          ></md-outlined-text-field>
        </div>

        <div v-if="currentMode === 'change_password'">
          <md-outlined-text-field
            label="原密码 (受信任宿主机桌面可留空)"
            type="password"
            :value="oldPassword"
            @input="oldPassword = ($event.target as any).value"
            :disabled="loading || lockoutSeconds > 0"
            class="w-full"
          ></md-outlined-text-field>
        </div>

        <div>
          <md-outlined-text-field
            :label="currentMode === 'change_password' ? '新密码 (至少 4 位)' : (currentMode === 'setup' ? '设置管理员密码 (至少 4 位)' : '管理员密码')"
            type="password"
            :value="password"
            @input="password = ($event.target as any).value"
            @keydown.enter="handleSubmit"
            :disabled="loading || lockoutSeconds > 0"
            class="w-full"
          ></md-outlined-text-field>
        </div>

        <div v-if="currentMode === 'setup' || currentMode === 'change_password'">
          <md-outlined-text-field
            label="确认新密码"
            type="password"
            :value="confirmPassword"
            @input="confirmPassword = ($event.target as any).value"
            @keydown.enter="handleSubmit"
            :disabled="loading || lockoutSeconds > 0"
            class="w-full"
          ></md-outlined-text-field>
        </div>
      </div>

      <!-- 安全说明 -->
      <div class="p-3 rounded-md bg-surface-card-sub border border-surface-border text-[11px] text-text-sub space-y-1">
        <div class="flex items-center gap-1.5 font-medium text-text-main">
          <M3Icon name="shield" :size="14" class="text-text-main" />
          <span>安全认证提示</span>
        </div>
        <p>• 登录凭据基于 SHA-256 加盐安全哈希存储，有效防范暴力碰撞与侧信道探测。</p>
        <p>• 连续输错密码 5 次将触发 5 分钟频控锁定，保障家庭局域网访问安全。</p>
      </div>
    </div>

    <template #actions>
      <button
        v-if="!forceModal"
        type="button"
        @click="handleClose"
        :disabled="loading"
        class="app-btn-secondary"
      >
        取消
      </button>
      <button
        type="button"
        @click="handleSubmit"
        :disabled="loading || lockoutSeconds > 0"
        class="app-btn-primary"
      >
        <M3Icon :name="loading ? 'sync' : 'check'" :size="16" :class="loading ? 'animate-spin' : ''" />
        <span>{{ currentMode === 'setup' ? '完成初始化并登录' : (currentMode === 'change_password' ? '保存新密码' : '立即登录') }}</span>
      </button>
    </template>
  </AppModal>
</template>
