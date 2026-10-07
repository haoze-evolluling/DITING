<script setup lang="ts">
import M3Icon from './M3Icon.vue';

defineProps<{
  title: string;
  value: string | number;
  unit?: string;
  icon: string;
  subtext?: string;
  trend?: string;
  color?: 'primary' | 'secondary' | 'tertiary' | 'error';
}>();
</script>

<template>
  <div
    class="relative overflow-hidden rounded-2xl p-5 border border-surface-border bg-surface-card shadow-xs transition-all duration-200 hover:shadow-md hover:border-brand-primary/30"
  >
    <div class="flex items-center justify-between mb-3">
      <span class="text-xs font-semibold text-text-sub uppercase tracking-wider">
        {{ title }}
      </span>
      <div
        class="flex items-center justify-center w-8 h-8 rounded-xl bg-surface-card-sub text-brand-primary"
      >
        <M3Icon :name="icon" :size="18" />
      </div>
    </div>
    <div class="flex items-baseline gap-1.5">
      <span class="text-2xl font-bold tracking-tight text-text-main">
        {{ value }}
      </span>
      <span v-if="unit" class="text-xs font-medium text-text-muted">
        {{ unit }}
      </span>
    </div>
    <div v-if="subtext" class="mt-2 text-xs text-text-sub flex items-center justify-between">
      <span>{{ subtext }}</span>
      <span v-if="trend" class="font-medium text-status-success">{{ trend }}</span>
    </div>
  </div>
</template>
