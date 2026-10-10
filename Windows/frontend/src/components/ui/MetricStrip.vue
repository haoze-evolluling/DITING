<script setup lang="ts">
/**
 * 指标带：横向排列的「散标签 + 大数值」组，靠发丝线分隔成表格式栅格。
 * 取代 4 个等宽圆角指标卡；数值用等宽大数字承载信息密度。
 * 用 auto-fit 网格，任意项数与任意屏宽下都不会出现错位分隔线。
 */
export interface StatEntry {
  label: string;
  value: string | number;
  unit?: string;
  /** 数值语气：默认墨；seal 用于被拦截等需朱色强调的项 */
  tone?: 'default' | 'seal' | 'muted';
}

withDefaults(
  defineProps<{
    stats: StatEntry[];
  }>(),
  {}
);

function valueClass(tone?: StatEntry['tone']) {
  switch (tone) {
    case 'seal':
      return 'text-accent-seal';
    case 'muted':
      return 'text-text-muted';
    default:
      return 'text-text-main';
  }
}
</script>

<template>
  <div
    class="app-panel grid gap-px bg-surface-border-sub overflow-hidden grid-cols-[repeat(auto-fit,minmax(9rem,1fr))]"
    role="group"
  >
    <div
      v-for="stat in stats"
      :key="stat.label"
      class="bg-surface-card px-4 py-3.5 min-w-0"
    >
      <div class="label-quiet">{{ stat.label }}</div>
      <div class="mt-1 flex items-baseline gap-1">
        <span
          class="font-mono text-[26px] font-semibold leading-none tracking-tight tabular-nums"
          :class="valueClass(stat.tone)"
        >
          {{ stat.value }}
        </span>
        <span v-if="stat.unit" class="text-[12px] text-text-muted">{{ stat.unit }}</span>
      </div>
    </div>
  </div>
</template>
