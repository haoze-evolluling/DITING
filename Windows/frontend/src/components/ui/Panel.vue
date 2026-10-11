<script setup lang="ts">
/**
 * 面板基元：纯平 surface + 1px 发丝线 + 6px 圆角，无阴影。
 */
withDefaults(
  defineProps<{
    title?: string;
    subtitle?: string;
    padded?: boolean;
  }>(),
  { title: '', subtitle: '', padded: true }
);
</script>

<template>
  <section class="app-panel overflow-hidden">
    <div
      v-if="title || $slots.actions"
      class="flex items-center justify-between gap-3 px-4 py-3 border-b border-surface-border"
    >
      <div class="min-w-0">
        <h3 v-if="title" class="section-title truncate">{{ title }}</h3>
        <p v-if="subtitle" class="mt-0.5 text-[12px] text-text-muted truncate">
          {{ subtitle }}
        </p>
      </div>
      <div v-if="$slots.actions" class="flex items-center gap-2 shrink-0">
        <slot name="actions" />
      </div>
    </div>
    <div :class="padded ? 'p-4' : ''">
      <slot />
    </div>
  </section>
</template>
