<script setup lang="ts">
import { watch, onUnmounted } from 'vue';

const props = withDefaults(
  defineProps<{
    open: boolean;
    title?: string;
    type?: 'alert' | 'info' | 'default';
    maxWidth?: string;
  }>(),
  {
    open: false,
    title: '',
    type: 'default',
    maxWidth: 'max-w-lg',
  }
);

const emit = defineEmits<{
  (e: 'close'): void;
}>();

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && props.open) {
    emit('close');
  }
}

watch(
  () => props.open,
  (val) => {
    if (val) {
      window.addEventListener('keydown', handleKeydown);
    } else {
      window.removeEventListener('keydown', handleKeydown);
    }
  },
  { immediate: true }
);

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeydown);
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs select-none"
        @click.self="emit('close')"
      >
        <div
          class="relative w-full rounded-2xl bg-surface-card border border-surface-border p-6 shadow-2xl transition-all flex flex-col gap-5 text-text-main"
          :class="maxWidth"
        >
          <!-- 标题区域 -->
          <div class="flex items-center gap-2">
            <slot name="headline">
              <span class="text-base font-bold tracking-tight text-text-main">{{ title }}</span>
            </slot>
          </div>

          <!-- 内容主体 -->
          <div class="text-sm text-text-sub leading-relaxed">
            <slot />
          </div>

          <!-- 底部操作按钮 -->
          <div class="flex items-center justify-end gap-3 pt-2">
            <slot name="actions" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
