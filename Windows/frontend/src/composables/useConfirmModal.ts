import { ref } from 'vue';

export interface ConfirmDialogOptions {
  title?: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  danger?: boolean;
  showCancel?: boolean;
}

/**
 * 确认弹窗状态管理（替代原生阻断式 window.confirm）
 */
export function useConfirmModal() {
  const isOpen = ref(false);
  const options = ref<ConfirmDialogOptions>({
    title: '确认操作',
    message: '',
    confirmText: '确定',
    cancelText: '取消',
    danger: false,
    showCancel: true,
  });

  let resolvePromise: ((value: boolean) => void) | null = null;

  function ask(opts: ConfirmDialogOptions): Promise<boolean> {
    options.value = {
      title: '确认操作',
      confirmText: '确定',
      cancelText: '取消',
      danger: false,
      showCancel: true,
      ...opts,
    };
    isOpen.value = true;
    return new Promise((resolve) => {
      resolvePromise = resolve;
    });
  }

  function handleConfirm() {
    isOpen.value = false;
    if (resolvePromise) {
      resolvePromise(true);
      resolvePromise = null;
    }
  }

  function handleCancel() {
    isOpen.value = false;
    if (resolvePromise) {
      resolvePromise(false);
      resolvePromise = null;
    }
  }

  return { isOpen, options, ask, handleConfirm, handleCancel };
}
