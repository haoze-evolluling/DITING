<script setup lang="ts">
/**
 * 页面题：宋体承担的类别标题 + 一行语境说明。
 * 右侧 actions 插槽放置页级操作，窄屏自动换行。
 */
withDefaults(
  defineProps<{
    title: string;
    subtitle?: string;
  }>(),
  { subtitle: '' }
);
</script>

<template>
  <header
    class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between sm:gap-6 mb-5"
  >
    <div class="min-w-0">
      <h1 class="page-title truncate">{{ title }}</h1>
      <p v-if="subtitle" class="mt-1 text-text-sub text-[13px] leading-relaxed">
        {{ subtitle }}
      </p>
    </div>
    <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2 shrink-0">
      <slot name="actions" />
    </div>
  </header>
</template>
