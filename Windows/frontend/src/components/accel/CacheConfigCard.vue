<script setup lang="ts">
import type { CacheConfig } from '../../api/types';
import M3Icon from '../M3Icon.vue';
import { extractSwitchValue } from '../../utils/switch';

defineProps<{
  config: CacheConfig;
  saving: boolean;
}>();

const emit = defineEmits<{
  (e: 'save'): void;
}>();
</script>

<template>
  <div class="p-6 rounded-md bg-surface-card border border-surface-border space-y-4">
    <div class="flex items-center justify-between gap-3">
      <h3 class="section-title">加速策略设置</h3>
      <button
        type="button"
        @click="emit('save')"
        :disabled="saving"
        class="app-btn-primary"
      >
        <M3Icon :name="saving ? 'refresh' : 'check'" :size="16" :class="saving ? 'animate-spin' : ''" />
        <span>{{ saving ? '保存中...' : '保存配置' }}</span>
      </button>
    </div>

    <div class="space-y-4 pt-1">
      <!-- TTL 策略模式 -->
      <div class="space-y-1">
        <label class="text-xs font-medium text-text-sub">有效期计算方式</label>
        <md-outlined-select :value="config.mode" @change="config.mode = ($event.target as any).value" class="w-full">
          <md-select-option value="limit_max_ttl"><div slot="headline">限制最长有效期 (推荐，避免过期失效)</div></md-select-option>
          <md-select-option value="follow_dns_ttl"><div slot="headline">完全遵从服务器给出的有效期</div></md-select-option>
          <md-select-option value="fixed_ttl"><div slot="headline">统一固定有效期</div></md-select-option>
        </md-outlined-select>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <md-outlined-text-field
          label="最长保存时长 (秒)"
          type="number"
          :value="String(config.maxTtlSeconds)"
          @input="config.maxTtlSeconds = Number(($event.target as any).value)"
        ></md-outlined-text-field>

        <md-outlined-text-field
          label="最短保留时长 (秒)"
          type="number"
          :value="String(config.minTtlSeconds)"
          @input="config.minTtlSeconds = Number(($event.target as any).value)"
        ></md-outlined-text-field>
      </div>

      <!-- Stale 容灾与 Optimistic SWR 开关 -->
      <div class="p-3 rounded-md bg-surface-card-sub border border-surface-border-sub space-y-3">
        <div class="flex items-center justify-between">
          <div>
            <span class="text-xs font-bold text-text-main">弱网应急保障 (旧记录兜底)</span>
            <p class="text-[11px] text-text-sub">当网络超时或波动时，临时使用近期缓存确保网页能正常打开</p>
          </div>
          <md-switch
            :selected="config.staleFallbackEnabled"
            @change="config.staleFallbackEnabled = extractSwitchValue($event)"
          ></md-switch>
        </div>

        <div v-if="config.staleFallbackEnabled" class="grid grid-cols-2 gap-3 pt-1">
          <md-outlined-text-field
            label="应急记录保留期 (秒)"
            type="number"
            :value="String(config.staleFallbackSeconds)"
            @input="config.staleFallbackSeconds = Number(($event.target as any).value)"
          ></md-outlined-text-field>

          <div class="flex items-center justify-between px-2">
            <span class="text-[11px] text-text-sub">极速响应 (先用缓存后后台更新)</span>
            <md-switch
              :selected="config.optimistic"
              @change="config.optimistic = extractSwitchValue($event)"
            ></md-switch>
          </div>
        </div>
      </div>

      <!-- 负缓存配置 -->
      <div class="p-3 rounded-md bg-surface-card-sub border border-surface-border-sub flex items-center justify-between">
        <div>
          <span class="text-xs font-bold text-text-main">无效网址记忆加速</span>
          <p class="text-[11px] text-text-sub">记住不存在或错误的网址，避免系统和软件频繁重复重试</p>
        </div>
        <md-switch
          :selected="config.negativeTtlEnabled"
          @change="config.negativeTtlEnabled = extractSwitchValue($event)"
        ></md-switch>
      </div>
    </div>
  </div>
</template>
