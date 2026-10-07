<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    status: 'active' | 'inactive' | 'warning' | 'error';
    text: string;
    pulse?: boolean;
    size?: 'sm' | 'md';
  }>(),
  {
    pulse: false,
    size: 'md',
  }
);

const badgeClasses = computed(() => {
  switch (props.status) {
    case 'active':
      return 'bg-status-success-bg text-status-success border-status-success/30';
    case 'warning':
      return 'bg-status-warning-bg text-status-warning border-status-warning/30';
    case 'error':
      return 'bg-status-error-bg text-status-error border-status-error/30';
    case 'inactive':
    default:
      return 'bg-surface-card-sub text-text-sub border-surface-border';
  }
});

const dotClasses = computed(() => {
  switch (props.status) {
    case 'active':
      return 'bg-status-success';
    case 'warning':
      return 'bg-status-warning';
    case 'error':
      return 'bg-status-error';
    case 'inactive':
    default:
      return 'bg-text-muted';
  }
});
</script>

<template>
  <span
    :class="[
      'inline-flex items-center gap-1.5 rounded-full border font-medium select-none transition-all duration-200',
      size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-xs',
      badgeClasses,
    ]"
  >
    <span class="relative flex h-2 w-2">
      <span
        v-if="pulse"
        :class="['animate-ping absolute inline-flex h-full w-full rounded-full opacity-75', dotClasses]"
      />
      <span :class="['relative inline-flex rounded-full h-2 w-2', dotClasses]" />
    </span>
    <span>{{ text }}</span>
  </span>
</template>
