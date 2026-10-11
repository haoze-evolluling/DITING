<script setup lang="ts">
import AppModal from './AppModal.vue';
import M3Icon from './M3Icon.vue';

withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    message: string;
    confirmText?: string;
    cancelText?: string;
    danger?: boolean;
    loading?: boolean;
    showCancel?: boolean;
  }>(),
  {
    title: '确认操作',
    confirmText: '确定',
    cancelText: '取消',
    danger: false,
    loading: false,
    showCancel: true,
  }
);

const emit = defineEmits<{
  (e: 'confirm'): void;
  (e: 'cancel'): void;
}>();
</script>

<template>
  <AppModal
    :open="open"
    @close="emit('cancel')"
    :type="danger ? 'alert' : 'default'"
    maxWidth="max-w-md"
  >
    <template #headline>
      <div class="flex items-center gap-2" :class="danger ? 'text-status-error font-bold' : 'text-text-main font-semibold'">
        <M3Icon :name="danger ? 'warning' : 'help_outline'" :size="20" />
        <span class="section-title">{{ title }}</span>
      </div>
    </template>

    <div class="space-y-2 py-1 text-xs sm:text-sm text-text-sub leading-relaxed">
      <p>{{ message }}</p>
    </div>

    <template #actions>
      <button
        v-if="showCancel"
        type="button"
        @click="emit('cancel')"
        :disabled="loading"
        class="app-btn-secondary"
      >
        {{ cancelText }}
      </button>
      <button
        type="button"
        @click="emit('confirm')"
        :disabled="loading"
        :class="danger ? 'app-btn-danger' : 'app-btn-primary'"
      >
        <M3Icon v-if="loading" name="refresh" class="animate-spin" :size="14" />
        <span>{{ confirmText }}</span>
      </button>
    </template>
  </AppModal>
</template>
