<script setup lang="ts">
import M3Icon from './M3Icon.vue';
import type { NavTab } from '../constants/navigation';

withDefaults(
  defineProps<{
    id: NavTab;
    label: string;
    icon: string;
    active: boolean;
    compact?: boolean;
  }>(),
  { compact: false }
);

const emit = defineEmits<{
  (e: 'navigate', tab: NavTab): void;
}>();
</script>

<template>
  <button
    v-if="!compact"
    type="button"
    @click="emit('navigate', id)"
    class="group relative flex flex-col items-center justify-center w-full py-2 rounded-2xl transition-all duration-200 cursor-pointer"
    :class="active ? 'text-brand-primary font-bold' : 'text-text-sub hover:text-text-main hover:bg-surface-hover'"
  >
    <div
      class="flex items-center justify-center w-14 h-8 rounded-full transition-all duration-200"
      :class="active ? 'bg-brand-container text-brand-on-container shadow-2xs' : 'text-inherit'"
    >
      <M3Icon :name="icon" :size="20" />
    </div>
    <span class="text-[11px] mt-1 tracking-tight">{{ label }}</span>
  </button>

  <button
    v-else
    type="button"
    @click="emit('navigate', id)"
    class="flex flex-col items-center justify-center py-1 flex-1 transition-colors cursor-pointer"
    :class="active ? 'text-brand-primary font-bold' : 'text-text-sub'"
  >
    <div
      class="flex items-center justify-center w-10 h-6 rounded-full transition-all"
      :class="active ? 'bg-brand-container text-brand-on-container shadow-2xs' : 'text-inherit'"
    >
      <M3Icon :name="icon" :size="18" />
    </div>
    <span class="text-[10px] tracking-tighter mt-0.5 truncate">{{ label }}</span>
  </button>
</template>
