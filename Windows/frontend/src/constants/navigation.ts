/** 侧边导航配置（App 与路由解析共用同一份定义） */

export type NavTab = 'dashboard' | 'adapters' | 'upstream' | 'cache' | 'rules' | 'logs' | 'settings';

export interface NavItemDef {
  id: NavTab;
  label: string;
  icon: string;
}

export const NAV_ITEMS: NavItemDef[] = [
  { id: 'dashboard', label: '运行总览', icon: 'dashboard' },
  { id: 'adapters', label: '网络接管', icon: 'adapters' },
  { id: 'upstream', label: 'DNS 服务', icon: 'upstream' },
  { id: 'cache', label: '解析加速', icon: 'cache' },
  { id: 'rules', label: '规则拦截', icon: 'shield' },
  { id: 'logs', label: '访问日志', icon: 'logs' },
  { id: 'settings', label: '设置中心', icon: 'settings' },
];

export const VALID_TABS: NavTab[] = NAV_ITEMS.map((item) => item.id);

export function isValidTab(value: string): value is NavTab {
  return (VALID_TABS as string[]).includes(value);
}
