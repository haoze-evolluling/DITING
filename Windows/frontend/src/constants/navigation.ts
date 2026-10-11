/** 侧边导航与类别配置（App 与路由解析共用同一份定义） */

export type NavTab = 'overview' | 'network' | 'accel' | 'rules' | 'system';

export interface NavItemDef {
  id: NavTab;
  label: string;
  icon: string;
  /** 顶栏语境说明 */
  hint: string;
}

export const NAV_ITEMS: readonly NavItemDef[] = [
  { id: 'overview', label: '总览', icon: 'dashboard', hint: '运行状态与实时查询流' },
  { id: 'network', label: '网络', icon: 'router', hint: '网卡接管 · 上游解析 · 局域网 DNS' },
  { id: 'accel', label: '加速', icon: 'speed', hint: '智能缓存与解析加速' },
  { id: 'rules', label: '规则', icon: 'shield', hint: '广告拦截与安全防护' },
  { id: 'system', label: '系统', icon: 'settings', hint: '外观 · 服务 · 局域网控制台' },
] as const;

export const VALID_TABS: readonly NavTab[] = NAV_ITEMS.map((item) => item.id);

/** 旧标签 id 到新五大类的重定向映射（保证书签与旧链接不失效） */
const LEGACY_TAB_MAP: Record<string, NavTab> = {
  dashboard: 'overview',
  logs: 'overview',
  adapters: 'network',
  upstream: 'network',
  cache: 'accel',
  rules: 'rules',
  settings: 'system',
};

export function isValidTab(value: string): value is NavTab {
  return (VALID_TABS as readonly string[]).includes(value);
}

/** 归一化任意标签值到当前有效的类别 id（含旧 id 重定向） */
export function normalizeTab(value: string): NavTab | null {
  const v = (value || '').toLowerCase();
  if (isValidTab(v)) return v;
  return LEGACY_TAB_MAP[v] ?? null;
}

export interface SubTabDef {
  id: string;
  label: string;
}

export const SUB_TABS: Record<NavTab, readonly SubTabDef[]> = {
  overview: [
    { id: 'status', label: '状态总览' },
    { id: 'queries', label: '实时查询' },
  ],
  network: [
    { id: 'adapters', label: '网卡接管' },
    { id: 'upstream', label: '上游解析' },
    { id: 'lan', label: '局域网 DNS' },
  ],
  accel: [
    { id: 'cache', label: '缓存加速' },
  ],
  rules: [
    { id: 'lists', label: '规则订阅' },
    { id: 'custom', label: '自定义规则' },
    { id: 'test', label: '规则检测' },
    { id: 'config', label: '拦截方式' },
  ],
  system: [
    { id: 'settings', label: '系统设置' },
  ],
};
