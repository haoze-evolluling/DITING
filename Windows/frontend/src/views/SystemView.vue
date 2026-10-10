<script setup lang="ts">
import PageHeader from '../components/ui/PageHeader.vue';
import SystemPanel from '../components/system/SystemPanel.vue';
</script>

<template>
  <div class="pb-12 select-none">
    <PageHeader
      title="系统"
      subtitle="外观主题、核心服务安装与局域网控制台，以及网络诊断与一键应急恢复。"
    />
    <SystemPanel />
  </div>
</template>
