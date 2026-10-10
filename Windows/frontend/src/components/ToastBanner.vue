<script setup lang="ts">
import M3Icon from './M3Icon.vue';

withDefaults(
  defineProps<{
    message: string;
    type?: 'success' | 'error';
    dismissible?: boolean;
    compact?: boolean;
  }>(),
  {
    type: 'success',
    dismissible: false,
    compact: false,
  }
);

const emit = defineEmits<{
  (e: 'dismiss'): void;
}>();
</script>

<template>
  <div
    v-if="message"
    class="rounded-xl border flex items-center justify-between gap-3"
    :class="[
      type === 'error'
        ? 'bg-status-error-bg border-status-error/20 text-status-error'
        : 'bg-status-success-bg border-status-success/20 text-status-success',
      compact ? 'p-3 text-xs' : 'px-4 py-3 text-sm',
    ]"
  >
    <div class="flex items-center gap-2 min-w-0">
      <M3Icon :name="type === 'error' ? 'error' : 'check_circle'" :size="18" class="shrink-0" />
      <span class="min-w-0">{{ message }}</span>
    </div>

    <div class="flex items-center gap-2 shrink-0">
      <slot name="actions" />
      <button
        v-if="dismissible"
        type="button"
        @click="emit('dismiss')"
        class="app-btn-secondary app-btn-compact"
      >
        关闭
      </button>
    </div>
  </div>
</template>
