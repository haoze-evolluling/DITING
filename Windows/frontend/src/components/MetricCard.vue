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
    class="relative overflow-hidden rounded-2xl p-5 border border-slate-200/40 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 shadow-sm backdrop-blur transition-all duration-200 hover:shadow-md"
  >
    <div class="flex items-center justify-between mb-3">
      <span class="text-xs font-medium text-slate-500 dark:text-slate-400 uppercase tracking-wider">
        {{ title }}
      </span>
      <div
        class="flex items-center justify-center w-8 h-8 rounded-xl bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300"
      >
        <M3Icon :name="icon" :size="18" />
      </div>
    </div>
    <div class="flex items-baseline gap-1.5">
      <span class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-50">
        {{ value }}
      </span>
      <span v-if="unit" class="text-xs font-semibold text-slate-500 dark:text-slate-400">
        {{ unit }}
      </span>
    </div>
    <div v-if="subtext" class="mt-2 text-xs text-slate-500 dark:text-slate-400 flex items-center justify-between">
      <span>{{ subtext }}</span>
      <span v-if="trend" class="font-medium text-emerald-600 dark:text-emerald-400">{{ trend }}</span>
    </div>
  </div>
</template>
