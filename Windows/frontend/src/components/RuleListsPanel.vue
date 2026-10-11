<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { ipc } from '../api/ipc';
import type { FilterList } from '../api/types';
import M3Icon from './M3Icon.vue';
import AppModal from './AppModal.vue';
import ConfirmModal from './ConfirmModal.vue';
import { useConfirmModal } from '../composables/useConfirmModal';
import { formatMonthDayTime } from '../utils/format';
import { extractSwitchValue, revertSwitch } from '../utils/switch';

const emit = defineEmits<{
  (e: 'error', message: string): void;
  (e: 'success', message: string): void;
  (e: 'changed'): void;
}>();

const lists = ref<FilterList[]>([]);
const refreshing = ref(false);
const saving = ref(false);
const isAddModalOpen = ref(false);
const newListName = ref('');
const newListURL = ref('');

const {
  isOpen: isDeleteConfirmOpen,
  options: deleteConfirmOptions,
  ask: askConfirm,
  handleConfirm: handleConfirmDelete,
  handleCancel: handleCancelDelete,
} = useConfirmModal();

function notify(message: string, isError: boolean) {
  if (isError) {
    emit('error', message);
  } else {
    emit('success', message);
  }
}

async function loadLists() {
  try {
    lists.value = await ipc.getFilterLists();
  } catch (err: any) {
    notify(err?.message || '获取规则库列表失败', true);
  }
}

async function handleAddList() {
  if (!newListURL.value.trim()) {
    notify('请输入有效的规则源 URL 或本地文件路径', true);
    return;
  }
  saving.value = true;
  try {
    const name = newListName.value.trim() || `订阅列表 ${lists.value.length + 1}`;
    await ipc.addFilterList({ name, url: newListURL.value.trim(), enabled: true });
    notify('规则库已添加并开始下载', false);
    isAddModalOpen.value = false;
    newListName.value = '';
    newListURL.value = '';
    await loadLists();
    emit('changed');
  } catch (err: any) {
    notify(err?.message || '添加规则库失败', true);
  } finally {
    saving.value = false;
  }
}

async function toggleList(list: FilterList, e: Event) {
  const nextVal = extractSwitchValue(e);
  const prevEnabled = list.enabled;
  try {
    list.enabled = nextVal;
    await ipc.updateFilterList(list);
    notify(`已${list.enabled ? '启用' : '停用'}规则库: ${list.name}`, false);
    await loadLists();
    emit('changed');
  } catch (err: any) {
    list.enabled = prevEnabled;
    revertSwitch(e, prevEnabled);
    notify(err?.message || '切换规则库状态失败', true);
  }
}

async function askDeleteList(list: FilterList) {
  const confirmed = await askConfirm({
    title: '删除规则库',
    message: `确定要删除规则库 [${list.name}] 吗？删除后其包含的拦截规则将不再生效。`,
    danger: true,
    confirmText: '确定删除',
  });
  if (!confirmed) return;
  try {
    await ipc.deleteFilterList(list.id);
    notify('已删除规则库', false);
    await loadLists();
    emit('changed');
  } catch (err: any) {
    notify(err?.message || '删除失败', true);
  }
}

async function refreshList(id?: string) {
  try {
    refreshing.value = true;
    await ipc.refreshFilterLists(id);
    notify(id ? '规则库已更新' : '全部规则库已更新完成', false);
    await loadLists();
    emit('changed');
  } catch (err: any) {
    notify(err?.message || '拉取规则失败', true);
  } finally {
    refreshing.value = false;
  }
}

onMounted(loadLists);
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <span class="text-xs text-text-sub">支持在线规则订阅链接与本地规则文本文件</span>
      <div class="flex items-center gap-3">
        <button type="button" @click="refreshList()" :disabled="refreshing" class="app-btn-secondary">
          <M3Icon name="refresh" :size="16" :class="refreshing ? 'animate-spin' : ''" />
          <span>{{ refreshing ? '正在下载更新...' : '全部更新' }}</span>
        </button>
        <button type="button" @click="isAddModalOpen = true" class="app-btn-primary">
          <M3Icon name="add" :size="16" />
          <span>添加规则库</span>
        </button>
      </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div
        v-for="l in lists"
        :key="l.id"
        class="p-5 rounded-md bg-surface-card border border-surface-border flex flex-col justify-between gap-4 transition-all duration-200"
      >
        <div>
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2 min-w-0">
              <span class="font-bold text-text-main truncate text-sm">{{ l.name }}</span>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-brand-container text-text-main shrink-0">
                {{ l.rulesCount.toLocaleString() }} 条规则
              </span>
            </div>
            <md-switch :selected="l.enabled" @change="(e: Event) => toggleList(l, e)"></md-switch>
          </div>
          <p class="text-xs text-text-muted font-mono mt-2 truncate select-all" :title="l.url">{{ l.url }}</p>
        </div>

        <div class="flex items-center justify-between pt-3 border-t border-surface-border-sub text-[11px] text-text-muted">
          <span>最后更新: {{ l.lastUpdated ? formatMonthDayTime(l.lastUpdated) : '未更新' }}</span>
          <div class="flex items-center gap-1.5">
            <button type="button" @click="refreshList(l.id)" class="app-btn-icon" title="立即更新">
              <M3Icon name="refresh" :size="14" />
            </button>
            <button type="button" @click="askDeleteList(l)" class="app-btn-icon app-btn-icon-danger" title="删除此规则库">
              <M3Icon name="delete" :size="14" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- 添加订阅弹窗 -->
    <AppModal :open="isAddModalOpen" @close="isAddModalOpen = false" title="添加规则订阅库">
      <div class="space-y-3 pt-1">
        <p class="text-xs text-text-sub">输入规则库的名称以及在线订阅网址 (URL) 或本地文件路径</p>
        <div>
          <label class="text-xs text-text-sub block mb-1">规则库名称</label>
          <input
            v-model="newListName"
            placeholder="例如: 广告拦截通用规则"
            class="w-full px-3 py-2 rounded-md border border-surface-border bg-surface-card-sub text-text-main text-sm focus:outline-none focus:border-accent-seal placeholder:text-text-muted"
          />
        </div>
        <div>
          <label class="text-xs text-text-sub block mb-1">订阅链接 / 文件路径</label>
          <input
            v-model="newListURL"
            placeholder="https://... 或本地文件路径"
            class="w-full px-3 py-2 rounded-md border border-surface-border bg-surface-card-sub text-text-main text-sm focus:outline-none focus:border-accent-seal placeholder:text-text-muted"
          />
        </div>
      </div>

      <template #actions>
        <button type="button" @click="isAddModalOpen = false" class="app-btn-secondary">取消</button>
        <button
          type="button"
          :disabled="saving || !newListURL.trim()"
          @click="handleAddList"
          class="app-btn-primary"
        >
          添加并下载
        </button>
      </template>
    </AppModal>

    <!-- 删除确认弹窗 -->
    <ConfirmModal
      :open="isDeleteConfirmOpen"
      :title="deleteConfirmOptions.title"
      :message="deleteConfirmOptions.message"
      :danger="deleteConfirmOptions.danger"
      :confirmText="deleteConfirmOptions.confirmText"
      :cancelText="deleteConfirmOptions.cancelText"
      :showCancel="deleteConfirmOptions.showCancel"
      @confirm="handleConfirmDelete"
      @cancel="handleCancelDelete"
    />
  </div>
</template>
