/**
 * 路由级 chunk 预取：导航项悬停/聚焦时提前加载对应页面模块，
 * 让日常跳转直接命中缓存，避免 Suspense 骨架与内容之间的二次闪烁。
 */
const routeLoaders: Record<string, () => Promise<unknown>> = {
  "/": () => import("../pages/dashboard-page"),
  "/logs": () => import("../pages/logs-page"),
  "/cache": () => import("../pages/cache-page"),
  "/filter": () => import("../pages/filter-page"),
  "/safety": () => import("../pages/safety-page"),
  "/advanced": () => import("../pages/advanced-page"),
  "/upstream": () => import("../pages/upstream-page"),
  "/rewrite": () => import("../pages/rewrite-page"),
  "/lan": () => import("../pages/lan-page"),
  "/encrypted": () => import("../pages/encrypted-page"),
  "/settings": () => import("../pages/settings-page"),
};

const prefetched = new Set<string>();
const pending = new Set<string>();

export function prefetchRoute(path: string): void {
  if (prefetched.has(path) || pending.has(path)) return;
  const loader = routeLoaders[path];
  if (!loader) return;

  pending.add(path);
  loader()
    .then(() => {
      prefetched.add(path);
    })
    .catch(() => undefined)
    .finally(() => {
      pending.delete(path);
    });
}
