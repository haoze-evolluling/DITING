<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    status: 'active' | 'inactive' | 'warning' | 'error';
    text: string;
    /** 亚秒级呼吸（透明度），尊重 prefers-reduced-motion */
    pulse?: boolean;
    size?: 'sm' | 'md';
  }>(),
  {
    pulse: false,
    size: 'md',
  }
);

const textClass = computed(() => {
  switch (props.status) {
    case 'active':
      return 'text-status-success';
    case 'warning':
      return 'text-status-warning';
    case 'error':
      return 'text-status-error';
    default:
      return 'text-text-muted';
  }
});

const dotClass = computed(() => {
  switch (props.status) {
    case 'active':
      return 'bg-status-success';
    case 'warning':
      return 'bg-status-warning';
    case 'error':
      return 'bg-status-error';
    default:
      return 'bg-text-muted';
  }
});
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 select-none"
    :class="size === 'sm' ? 'text-[12px]' : 'text-[13px]'"
  >
    <span class="w-1.5 h-1.5 rounded-full shrink-0" :class="[dotClass, pulse ? 'seal-pulse' : '']" />
    <span class="font-medium" :class="textClass">{{ text }}</span>
  </span>
</template>
