<script setup lang="ts">
import { ref, watch } from 'vue';
import PageHeader from '../components/ui/PageHeader.vue';
import SegmentedTabs from '../components/ui/SegmentedTabs.vue';
import OverviewPanel from '../components/overview/OverviewPanel.vue';
import LiveQueryPanel from '../components/overview/LiveQueryPanel.vue';
import { SUB_TABS, type NavTab } from '../constants/navigation';

const props = defineProps<{ sub?: string }>();
const emit = defineEmits<{
  (e: 'navigate', tab: NavTab): void;
}>();

const segments = SUB_TABS.overview ?? [];
const active = ref(
  props.sub && segments.some((s) => s.id === props.sub) ? props.sub : (segments[0]?.id ?? 'status')
);

watch(
  () => props.sub,
  (v) => {
    if (v && segments.some((s) => s.id === v)) active.value = v;
  }
);
</script>

<template>
  <div class="pb-12 select-none">
    <PageHeader
      title="总览"
      subtitle="掌握 DNS 解析加速与安全防护的实时运行状态。"
    />
    <SegmentedTabs v-model="active" :segments="segments" />

    <OverviewPanel
      v-if="active === 'status'"
      @navigate="emit('navigate', $event)"
    />
    <LiveQueryPanel v-else />
  </div>
</template>
