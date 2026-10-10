import { onMounted, onUnmounted } from 'vue';

/**
 * 定时轮询 composable：挂载后立即执行一次并按时启动，卸载时自动清理。
 */
export function usePoller(task: () => void | Promise<void>, intervalMs: number) {
  let timer: ReturnType<typeof setInterval> | null = null;

  onMounted(() => {
    task();
    timer = setInterval(task, intervalMs);
  });

  onUnmounted(() => {
    if (timer) clearInterval(timer);
    timer = null;
  });
}
