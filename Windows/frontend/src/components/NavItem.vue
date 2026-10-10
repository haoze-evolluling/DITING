<script setup lang="ts">
import M3Icon from './M3Icon.vue';
import type { NavTab } from '../constants/navigation';

withDefaults(
  defineProps<{
    id: NavTab;
    label: string;
    icon: string;
    active: boolean;
    /** 中屏图标栏 / 小屏底部栏：纯图标 + 小字 */
    iconOnly?: boolean;
  }>(),
  { iconOnly: false }
);

const emit = defineEmits<{
  (e: 'navigate', tab: NavTab): void;
}>();
</script>

<template>
  <!-- 纯图标态（中屏图标栏 / 小屏底部栏） -->
  <button
    v-if="iconOnly"
    type="button"
    :title="label"
    :aria-label="label"
    :aria-current="active ? 'page' : undefined"
    @click="emit('navigate', id)"
    class="relative flex flex-col items-center justify-center gap-1 py-1.5 flex-1 transition-colors cursor-pointer"
    :class="active ? 'text-text-main' : 'text-text-muted hover:text-text-sub'"
  >
    <M3Icon :name="icon" :size="20" />
    <span class="text-[10px] leading-none truncate max-w-full px-0.5">{{ label }}</span>
    <span
      v-if="active"
      class="absolute top-0 left-1/2 -translate-x-1/2 w-5 h-0.5 rounded-full bg-accent-seal"
    />
  </button>

  <!-- 文本行态（宽侧栏）：左侧朱色竖条 + 底纹 -->
  <button
    v-else
    type="button"
    :aria-current="active ? 'page' : undefined"
    @click="emit('navigate', id)"
    class="relative flex items-center gap-3 w-full pl-4 pr-3 py-2.5 text-[13.5px] transition-colors cursor-pointer"
    :class="
      active
        ? 'bg-surface-card-sub text-text-main font-semibold'
        : 'text-text-sub hover:bg-surface-hover hover:text-text-main'
    "
  >
    <span
      class="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[2px] rounded-r-full bg-accent-seal transition-opacity"
      :class="active ? 'opacity-100' : 'opacity-0'"
    />
    <M3Icon :name="icon" :size="18" />
    <span class="truncate">{{ label }}</span>
  </button>
</template>
