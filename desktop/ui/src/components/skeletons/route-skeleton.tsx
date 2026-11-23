import type { ComponentType } from "react";

import {
  AdvancedSkeleton,
  CacheSkeleton,
  DashboardSkeleton,
  EncryptedSkeleton,
  FilterSkeleton,
  GenericPageSkeleton,
  LanSkeleton,
  LogsSkeleton,
  RewriteSkeleton,
  SafetySkeleton,
  SettingsSkeleton,
  UpstreamSkeleton,
} from "./pages";

/**
 * 路由 → 骨架模板。新增页面时在这里补一条，骨架即可按该页真实网格排布；
 * 未登记的路由回退到通用骨架，不会出现空白或布局塌陷。
 */
const ROUTE_SKELETONS: Record<string, ComponentType> = {
  "/": DashboardSkeleton,
  "/logs": LogsSkeleton,
  "/cache": CacheSkeleton,
  "/filter": FilterSkeleton,
  "/safety": SafetySkeleton,
  "/advanced": AdvancedSkeleton,
  "/upstream": UpstreamSkeleton,
  "/rewrite": RewriteSkeleton,
  "/lan": LanSkeleton,
  "/encrypted": EncryptedSkeleton,
  "/settings": SettingsSkeleton,
};

function normalizePath(pathname: string): string {
  const trimmed = pathname.replace(/\/+$/, "");
  return trimmed || "/";
}

export function RouteSkeleton({ pathname }: { pathname: string }) {
  const Template = ROUTE_SKELETONS[normalizePath(pathname)] ?? GenericPageSkeleton;
  return (
    <div role="status" aria-live="polite" aria-label="正在加载页面">
      <Template />
    </div>
  );
}
