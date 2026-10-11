<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    data: number[];
    maxPoints?: number;
    height?: number;
    strokeColor?: string;
    label?: string;
    unit?: string;
  }>(),
  {
    maxPoints: 30,
    height: 120,
    strokeColor: '',
    label: '',
    unit: '',
  }
);

const viewBox = computed(() => `0 0 500 ${props.height}`);

const stroke = computed(() =>
  props.strokeColor ? props.strokeColor : 'var(--app-text-main)'
);

const points = computed(() => {
  const list = props.data && props.data.length > 0 ? props.data : [0];
  const max = Math.max(...list, 1);
  const min = 0;
  const range = max - min || 1;
  const count = Math.max(list.length, 2);
  const stepX = 500 / (count - 1);

  return list.map((val, idx) => {
    const x = idx * stepX;
    const normalized = (val - min) / range;
    const y = props.height - 10 - normalized * (props.height - 24);
    return { x, y, val };
  });
});

const pathString = computed(() => {
  if (points.value.length === 0) return '';
  const pts = points.value;
  if (pts.length === 1) return `M 0 ${pts[0].y} L 500 ${pts[0].y}`;

  let d = `M ${pts[0].x} ${pts[0].y}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i];
    const p1 = pts[i + 1];
    const mx = (p0.x + p1.x) / 2;
    d += ` C ${mx} ${p0.y}, ${mx} ${p1.y}, ${p1.x} ${p1.y}`;
  }
  return d;
});

const latestValue = computed(() => {
  if (!props.data || props.data.length === 0) return 0;
  return props.data[props.data.length - 1];
});

const gridLines = computed(() => {
  const h = props.height;
  return [0.25, 0.5, 0.75].map((r) => h - 10 - r * (h - 24));
});
</script>

<template>
  <div class="app-panel p-4">
    <div class="flex items-baseline justify-between mb-2">
      <span class="label-quiet">{{ label }}</span>
      <span class="text-[12px] text-text-muted">
        当前
        <strong class="font-mono text-[15px] font-semibold text-text-main">{{ latestValue.toFixed(1) }}</strong>
        <span class="ml-0.5">{{ unit }}</span>
      </span>
    </div>

    <div class="w-full overflow-hidden">
      <svg :viewBox="viewBox" class="w-full overflow-visible" preserveAspectRatio="none" :height="height">
        <line
          v-for="(y, i) in gridLines"
          :key="i"
          x1="0"
          :y1="y"
          x2="500"
          :y2="y"
          stroke="var(--app-surface-border-sub)"
          stroke-width="1"
        />
        <path
          :d="pathString"
          fill="none"
          :stroke="stroke"
          stroke-width="1.75"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <circle
          v-if="points.length > 0"
          :cx="points[points.length - 1].x"
          :cy="points[points.length - 1].y"
          r="2.5"
          :fill="stroke"
        />
      </svg>
    </div>
  </div>
</template>
