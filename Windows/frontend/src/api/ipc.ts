import type { WebSocketEvent } from './types';
import { HttpTransport } from './http';
import { EventChannel } from './ws';
import { CoreApi } from './core';
import { CacheApi } from './cache';
import { FilterApi } from './filter';
import { NetworkApi } from './network';
import { WebAuthApi } from './web';
import { nativeBridge } from './native';
import { isWebMode } from '../utils/env';

/**
 * IPC 服务聚合门面。
 * 统一组合传输、事件通道、平台桥接与各领域模块。
 */
class IPCService {
  private http = new HttpTransport();
  private events = new EventChannel(this.http);

  private core = new CoreApi(this.http);
  private cache = new CacheApi(this.http);
  private filter = new FilterApi(this.http);
  private network = new NetworkApi(this.http);
  private webAuth = new WebAuthApi(this.http, this.events);

  // --- 环境与连接 ---
  public isWebMode = () => isWebMode();
  public onConnectionChange = (l: (c: boolean) => void) => this.http.onConnectionChange(l);
  public onAuthRequired = (l: (r: boolean) => void) => this.http.onAuthRequired(l);
  public onEvent = (l: (e: WebSocketEvent) => void) => this.events.subscribe(l);
  public connectWS = () => this.events.connect();
  public reconnectWS = () => this.events.reconnect();
  public checkHealth = () => this.core.checkHealth();

  get isConnected(): boolean {
    return this.http.isConnected;
  }

  // --- 连接配置 ---
  public loadConfig = () => this.http.loadConfig();
  public saveConfig = (host: string, port: string, token: string) => this.http.saveConfig(host, port, token);
  public getConfig = () => this.http.getConfig();

  // --- 核心状态与 DNS 服务 ---
  public getStatus = () => this.core.getStatus();
  public startDNS = () => this.core.startDNS();
  public stopDNS = () => this.core.stopDNS();
  public enableTakeover = () => this.core.enableTakeover();
  public disableTakeover = () => this.core.disableTakeover();
  public getAdapters = () => this.core.getAdapters();
  public setAdapterTakeover = (id: string, enable: boolean) => this.core.setAdapterTakeover(id, enable);
  public checkPortConflicts = () => this.core.checkPortConflicts();
  public autofixPortConflicts = (startDNS = false) => this.core.autofixPortConflicts(startDNS);

  // --- 上游与 Bootstrap ---
  public configureUpstream = (req: Parameters<CoreApi['configureUpstream']>[0]) => this.core.configureUpstream(req);
  public testUpstream = (req: Parameters<CoreApi['testUpstream']>[0]) => this.core.testUpstream(req);
  public configureBootstrap = (cfg: Parameters<CoreApi['configureBootstrap']>[0]) => this.core.configureBootstrap(cfg);

  // --- 智能缓存 ---
  public getCacheStats = () => this.cache.getStats();
  public getCacheEntries = (query = '', limit = 50) => this.cache.getEntries(query, limit);
  public getCacheTopDomains = (limit = 10) => this.cache.getTopDomains(limit);
  public clearCache = () => this.cache.clear();
  public getCacheConfig = () => this.cache.getConfig();
  public updateCacheConfig = (cfg: Parameters<CacheApi['updateConfig']>[0]) => this.cache.updateConfig(cfg);

  // --- 规则拦截 ---
  public getFilterStats = () => this.filter.getStats();
  public getFilterConfig = () => this.filter.getConfig();
  public updateFilterConfig = (cfg: Parameters<FilterApi['updateConfig']>[0]) => this.filter.updateConfig(cfg);
  public getFilterLists = () => this.filter.getLists();
  public addFilterList = (l: Parameters<FilterApi['addList']>[0]) => this.filter.addList(l);
  public updateFilterList = (l: Parameters<FilterApi['updateList']>[0]) => this.filter.updateList(l);
  public deleteFilterList = (id: string) => this.filter.deleteList(id);
  public refreshFilterLists = (id = '') => this.filter.refreshLists(id);
  public getCustomRules = () => this.filter.getCustomRules();
  public setCustomRules = (rules: string[]) => this.filter.setCustomRules(rules);
  public checkHost = (domain: string, qtype: string | number = 'A') => this.filter.checkHost(domain, qtype);

  // --- 局域网 DNS ---
  public getLANStatus = () => this.network.getLANStatus();
  public configureLAN = (req: Parameters<NetworkApi['configureLAN']>[0]) => this.network.configureLAN(req);
  public configureFirewall = (enable: boolean) => this.network.configureFirewall(enable);
  public configureWebFirewall = (enable: boolean) => this.network.configureWebFirewall(enable);

  // --- Web 远程管理认证 ---
  public getAuthStatus = () => this.webAuth.getAuthStatus();
  public login = (req: Parameters<WebAuthApi['login']>[0]) => this.webAuth.login(req);
  public logout = () => this.webAuth.logout();
  public setupAuth = (req: Parameters<WebAuthApi['setupAuth']>[0]) => this.webAuth.setupAuth(req);
  public changePassword = (req: Parameters<WebAuthApi['changePassword']>[0]) => this.webAuth.changePassword(req);
  public getWebStatus = () => this.webAuth.getWebStatus();
  public configureWeb = (req: Parameters<WebAuthApi['configureWeb']>[0]) => this.webAuth.configureWeb(req);

  // --- Wails 原生平台委托 ---
  public runNativeEmergencyRestore = () => nativeBridge.runNativeEmergencyRestore();
  public isAutoStartEnabled = () => nativeBridge.isAutoStartEnabled();
  public setAutoStart = (enable: boolean) => nativeBridge.setAutoStart(enable);
  public getCoreServiceStatus = () => nativeBridge.getCoreServiceStatus();
  public startCoreService = () => nativeBridge.startCoreService();
  public stopCoreService = () => nativeBridge.stopCoreService();
  public restartCoreService = () => nativeBridge.restartCoreService();
  public installCoreService = () => nativeBridge.installCoreService();
  public installAndStartCoreService = () => nativeBridge.installAndStartCoreService();
  public uninstallCoreService = () => nativeBridge.uninstallCoreService();
}

export const ipc = new IPCService();
