<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    data: number[];
    maxPoints?: number;
    height?: number;
    strokeColor?: string;
    gradientId?: string;
    label?: string;
    unit?: string;
  }>(),
  {
    maxPoints: 30,
    height: 120,
    strokeColor: '#00668b',
    gradientId: 'chart-grad-primary',
    label: '',
    unit: '',
  }
);

const viewBox = computed(() => `0 0 500 ${props.height}`);

const points = computed(() => {
  const list = props.data.length > 0 ? props.data : [0];
  const max = Math.max(...list, 1);
  const min = 0;
  const range = max - min;
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

const areaString = computed(() => {
  if (!pathString.value) return '';
  const pts = points.value;
  const last = pts[pts.length - 1];
  return `${pathString.value} L ${last.x} ${props.height} L ${pts[0].x} ${props.height} Z`;
});

const latestValue = computed(() => {
  if (props.data.length === 0) return 0;
  return props.data[props.data.length - 1];
});
</script>

<template>
  <div class="relative w-full rounded-2xl border border-slate-200/40 dark:border-slate-800/80 bg-white/70 dark:bg-slate-900/60 p-4 shadow-sm backdrop-blur">
    <div class="flex items-center justify-between mb-2">
      <span class="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
        {{ label }}
      </span>
      <span class="text-xs font-medium text-slate-700 dark:text-slate-300">
        当前: <strong class="text-sm font-bold text-slate-900 dark:text-slate-100">{{ latestValue.toFixed(1) }}</strong> {{ unit }}
      </span>
    </div>

    <div class="w-full overflow-hidden rounded-xl bg-slate-50/50 dark:bg-slate-950/40">
      <svg :viewBox="viewBox" class="w-full overflow-visible" preserveAspectRatio="none" :height="height">
        <defs>
          <linearGradient :id="gradientId" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" :stop-color="strokeColor" stop-opacity="0.35" />
            <stop offset="100%" :stop-color="strokeColor" stop-opacity="0.0" />
          </linearGradient>
        </defs>

        <path :d="areaString" :fill="`url(#${gradientId})`" />
        <path :d="pathString" fill="none" :stroke="strokeColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
        <circle
          v-if="points.length > 0"
          :cx="points[points.length - 1].x"
          :cy="points[points.length - 1].y"
          r="4"
          :fill="strokeColor"
          class="animate-pulse"
        />
      </svg>
    </div>
  </div>
</template>
