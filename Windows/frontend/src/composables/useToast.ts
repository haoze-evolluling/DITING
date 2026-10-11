import { ref } from 'vue';

export interface ToastState {
  message: string;
  isError: boolean;
}

/**
 * 轻量消息提示状态：统一管理成功/失败横幅文案与自动消隐。
 */
export function useToast(defaultDurationMs = 3000) {
  const toast = ref<ToastState | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;

  function show(message: string, isError = false, holdMs = defaultDurationMs) {
    if (timer) clearTimeout(timer);
    toast.value = { message, isError };
    timer = setTimeout(() => {
      toast.value = null;
      timer = null;
    }, holdMs);
  }

  function success(message: string, holdMs = defaultDurationMs) {
    show(message, false, holdMs);
  }

  function error(message: string, holdMs = defaultDurationMs + 1000) {
    show(message, true, holdMs);
  }

  function dismiss() {
    if (timer) clearTimeout(timer);
    timer = null;
    toast.value = null;
  }

  return { toast, show, success, error, dismiss };
}
