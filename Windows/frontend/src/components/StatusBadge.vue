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
      return 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border-emerald-500/30';
    case 'warning':
      return 'bg-amber-500/15 text-amber-600 dark:text-amber-400 border-amber-500/30';
    case 'error':
      return 'bg-rose-500/15 text-rose-600 dark:text-rose-400 border-rose-500/30';
    case 'inactive':
    default:
      return 'bg-slate-500/15 text-slate-500 dark:text-slate-400 border-slate-500/30';
  }
});

const dotClasses = computed(() => {
  switch (props.status) {
    case 'active':
      return 'bg-emerald-500';
    case 'warning':
      return 'bg-amber-500';
    case 'error':
      return 'bg-rose-500';
    case 'inactive':
    default:
      return 'bg-slate-400';
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
