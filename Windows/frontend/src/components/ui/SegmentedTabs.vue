<script setup lang="ts">
/**
 * 分段页签（Segment Tabs）：类别内多段内容的二级导航。
 * 墨色 active=底纹 + 下缘朱色细线，不用胶囊 pill、不用发光。
 */
export interface SegmentDef {
  id: string;
  label: string;
}

defineProps<{
  segments: SegmentDef[];
  modelValue: string;
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();
</script>

<template>
  <div
    class="flex items-stretch gap-1 overflow-x-auto border-b border-surface-border mb-5"
    role="tablist"
  >
    <button
      v-for="seg in segments"
      :key="seg.id"
      type="button"
      role="tab"
      :aria-selected="modelValue === seg.id"
      class="relative shrink-0 px-3.5 py-2.5 text-[13px] font-semibold transition-colors cursor-pointer whitespace-nowrap"
      :class="
        modelValue === seg.id
          ? 'text-text-main'
          : 'text-text-muted hover:text-text-sub'
      "
      @click="emit('update:modelValue', seg.id)"
    >
      {{ seg.label }}
      <span
        v-if="modelValue === seg.id"
        class="absolute left-0 right-0 -bottom-px h-0.5 bg-accent-seal"
      />
    </button>
  </div>
</template>
