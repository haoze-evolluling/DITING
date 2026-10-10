<script setup lang="ts">
import { ref, watch } from 'vue';
import PageHeader from '../components/ui/PageHeader.vue';
import SegmentedTabs from '../components/ui/SegmentedTabs.vue';
import RulesPanel from '../components/rules/RulesPanel.vue';
import { SUB_TABS } from '../constants/navigation';

const props = defineProps<{ sub?: string }>();

const segments = SUB_TABS.rules ?? [];
const active = ref(
  props.sub && segments.some((s) => s.id === props.sub) ? props.sub : (segments[0]?.id ?? 'lists')
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
      title="拦截规则"
      subtitle="基于 AdGuard 语法的规则引擎：订阅远程规则库、编写自定义规则、实时检测域名，并选择拦截响应方式。"
    />

    <SegmentedTabs v-model="active" :segments="segments" />

    <RulesPanel v-model:sub="active" />
  </div>
</template>
