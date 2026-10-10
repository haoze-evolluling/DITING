<script setup lang="ts">
import PageHeader from '../components/ui/PageHeader.vue';
import CachePanel from '../components/accel/CachePanel.vue';
</script>

<template>
  <div class="pb-12 select-none">
    <PageHeader
      title="加速"
      subtitle="本地分片缓存加速解析，配合容灾复用与请求合并，兼顾实时性与响应效率。"
    />
    <CachePanel />
  </div>
</template>
