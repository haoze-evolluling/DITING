import { ref } from 'vue';
import { copyToClipboard } from '../utils/clipboard';

/**
 * 复制到剪贴板并给出「已复制」短反馈（自动消隐）。
 */
export function useCopyFeedback(holdMs = 2000) {
  const copiedValue = ref<string | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;

  async function copy(value: string): Promise<boolean> {
    const ok = await copyToClipboard(value);
    if (ok) {
      copiedValue.value = value;
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        if (copiedValue.value === value) copiedValue.value = null;
        timer = null;
      }, holdMs);
    }
    return ok;
  }

  const isCopied = (value: string) => copiedValue.value === value;

  return { copiedValue, copy, isCopied };
}
