import { useAuthStore } from "../stores/auth";

import type {
  AdapterInfo,
  ApiEnvelope,
  AuthStatus,
  BlockedServicesResponse,
  BlockingSchedule,
  CheckHostResult,
  EmergencyRestoreResult,
  EncryptedDNSStatus,
  FilterConfig,
  FilterList,
  FilterListsResponse,
  FilterPauseResponse,
  FilterRulesResponse,
  FilterStats,
  LanStatus,
  LoginResult,
  MetaInfo,
  PortCheckResult,
  ProviderConfig,
  QueryLogConfig,
  QueryLogStats,
  QuerySearchParams,
  QuerySearchResult,
  ResolverConfig,
  ScheduleConfigResponse,
  ServiceStatus,
  StampParseResult,
  StatusResponse,
  UpstreamTestResult,
} from "./types";

export class ApiError extends Error {
  status: number;
  conflict?: unknown;

  constructor(message: string, status = 0, conflict?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.conflict = conflict;
  }
}

interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | boolean | undefined>;
  signal?: AbortSignal;
  auth?: boolean;
}

function buildUrl(path: string, query?: RequestOptions["query"]): string {
  const url = path;
  if (!query) return url;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === "") continue;
    params.set(key, String(value));
  }
  const suffix = params.toString();
  return suffix ? `${url}?${suffix}` : url;
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, query, signal, auth = true } = options;
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (auth) {
    const token = useAuthStore.getState().token;
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  let response: Response;
  try {
    response = await fetch(buildUrl(path, query), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    throw new ApiError(
      "无法连接谛听管理服务。请确认 diting-service 正在运行，并检查管理端口。",
    );
  }

  const text = await response.text();
  let payload: ApiEnvelope<T> | null = null;
  if (text) {
    try {
      payload = JSON.parse(text) as ApiEnvelope<T>;
    } catch {
      payload = null;
    }
  }

  if (response.status === 401 && path !== "/api/v1/auth/login") {
    useAuthStore.getState().clear();
  }

  if (!response.ok || !payload || payload.success === false) {
    const message =
      payload?.error ||
      payload?.message ||
      `请求失败（HTTP ${response.status}）`;
    throw new ApiError(message, response.status, payload?.conflict);
  }

  return payload.data as T;
}

export const api = {
  health: () => request<string>("/api/v1/health", { auth: false }),
  meta: () => request<MetaInfo>("/api/v1/meta", { auth: false }),
  authStatus: () => request<AuthStatus>("/api/v1/auth/status", { auth: false }),

  setup: (username: string, password: string) =>
    request<void>("/api/v1/auth/setup", {
      method: "POST",
      body: { username, password },
      auth: false,
    }),

  login: (username: string, password: string) =>
    request<LoginResult>("/api/v1/auth/login", {
      method: "POST",
      body: { username, password },
      auth: false,
    }),

  logout: () => request<void>("/api/v1/auth/logout", { method: "POST" }),

  status: () => request<StatusResponse>("/api/v1/status"),
  serviceStatus: () => request<ServiceStatus>("/api/v1/service/status"),
  adapters: () => request<AdapterInfo[]>("/api/v1/adapters"),

  startDns: () => request<void>("/api/v1/dns/start", { method: "POST" }),
  stopDns: () => request<void>("/api/v1/dns/stop", { method: "POST" }),
  enableTakeover: () =>
    request<void>("/api/v1/takeover/enable", { method: "POST" }),
  disableTakeover: () =>
    request<void>("/api/v1/takeover/disable", { method: "POST" }),
  setAdapterTakeover: (adapterId: string, enable: boolean) =>
    request<void>("/api/v1/takeover/adapter", {
      method: "POST",
      body: { adapterId, enable },
    }),
  emergencyRestore: () =>
    request<EmergencyRestoreResult>("/api/v1/takeover/emergency-restore", {
      method: "POST",
    }),

  portCheck: () => request<PortCheckResult>("/api/v1/portcheck"),
  portAutofix: (startDns: boolean) =>
    request<PortCheckResult>("/api/v1/portcheck/autofix", {
      method: "POST",
      body: { startDNS: startDns },
    }),

  queryStats: () => request<QueryLogStats>("/api/v1/querylog/stats"),
  querySearch: (params: QuerySearchParams) =>
    request<QuerySearchResult>("/api/v1/querylog/search", {
      query: { ...params, includeFile: true },
    }),
  queryConfig: () => request<QueryLogConfig>("/api/v1/querylog/config"),
  updateQueryConfig: (patch: Partial<QueryLogConfig>) =>
    request<void>("/api/v1/querylog/config", { method: "POST", body: patch }),
  clearQueryLog: () =>
    request<void>("/api/v1/querylog/clear", { method: "POST" }),

  // 上游解析
  upstreamConfig: () => request<ResolverConfig>("/api/v1/upstream"),
  configureUpstream: (patch: Partial<ResolverConfig>) =>
    request<void>("/api/v1/upstream/configure", { method: "POST", body: patch }),
  testUpstream: (provider: Pick<ProviderConfig, "protocol" | "server" | "url">) =>
    request<UpstreamTestResult>("/api/v1/upstream/test", {
      method: "POST",
      body: provider,
    }),
  configureBootstrap: (patch: {
    enabled?: boolean;
    servers: { id: string; name: string; address: string; weight?: number }[];
  }) =>
    request<void>("/api/v1/bootstrap/configure", { method: "POST", body: patch }),
  parseStamp: (stamp: string) =>
    request<StampParseResult>("/api/v1/upstream/stamp", {
      method: "POST",
      body: { stamp },
    }),

  // 规则与拦截
  filterStats: () => request<FilterStats>("/api/v1/filter/stats"),
  filterConfig: () => request<FilterConfig>("/api/v1/filter/config"),
  updateFilterConfig: (patch: Partial<FilterConfig>) =>
    request<void>("/api/v1/filter/config", { method: "POST", body: patch }),
  filterLists: () => request<FilterListsResponse>("/api/v1/filter/lists"),
  addFilterList: (list: Partial<FilterList>) =>
    request<void>("/api/v1/filter/lists/add", { method: "POST", body: list }),
  updateFilterList: (list: FilterList) =>
    request<void>("/api/v1/filter/lists/update", { method: "POST", body: list }),
  deleteFilterList: (id: string) =>
    request<void>("/api/v1/filter/lists/delete", { method: "POST", body: { id } }),
  refreshFilterLists: (id?: string) =>
    request<void>("/api/v1/filter/lists/refresh", {
      method: "POST",
      body: id ? { id } : {},
    }),
  customRules: () => request<FilterRulesResponse>("/api/v1/filter/rules"),
  saveCustomRules: (rules: string[]) =>
    request<void>("/api/v1/filter/rules", { method: "POST", body: { rules } }),
  checkDomain: (domain: string, qtype = "A") =>
    request<CheckHostResult>("/api/v1/filter/check", {
      method: "POST",
      body: { domain, qtype },
    }),
  filterSchedule: () =>
    request<ScheduleConfigResponse>("/api/v1/filter/schedule"),
  configureSchedule: (patch: {
    enabled?: boolean;
    schedules?: BlockingSchedule[];
  }) =>
    request<void>("/api/v1/filter/schedule", { method: "POST", body: patch }),
  filterPause: () => request<FilterPauseResponse>("/api/v1/filter/pause"),
  setFilterPause: (paused: boolean, durationSec = 0) =>
    request<void>("/api/v1/filter/pause", {
      method: "POST",
      body: { paused, durationSec },
    }),
  blockedServices: () =>
    request<BlockedServicesResponse>("/api/v1/filter/services"),
  configureBlockedServices: (patch: {
    ids?: string[];
    groups?: string[];
    schedules?: Record<string, BlockingSchedule[]>;
  }) =>
    request<BlockedServicesResponse>("/api/v1/filter/services", {
      method: "POST",
      body: patch,
    }),

  // 局域网与客户端
  lanStatus: () => request<LanStatus>("/api/v1/dns/lan"),
  configureLan: (allowLAN: boolean, configureFirewall: boolean) =>
    request<void>("/api/v1/dns/lan/configure", {
      method: "POST",
      body: { allowLAN, configureFirewall },
    }),
  configureLanFirewall: (enable: boolean) =>
    request<void>("/api/v1/dns/lan/firewall", {
      method: "POST",
      body: { enable },
    }),
  configureAccess: (allowedClients: string[], blockedClients: string[]) =>
    request<void>("/api/v1/dns/access/configure", {
      method: "POST",
      body: { allowedClients, blockedClients },
    }),
  configureRateLimit: (patch: {
    enabled: boolean;
    rate: number;
    burst: number;
    ipv4Prefix: number;
    ipv6Prefix: number;
    exemptIPs: string[];
  }) =>
    request<void>("/api/v1/dns/ratelimit/configure", {
      method: "POST",
      // 状态接口返回 exemptIPs，但请求结构体按 camelCase 推导为 exemptIps。
      body: {
        enabled: patch.enabled,
        rate: patch.rate,
        burst: patch.burst,
        ipv4Prefix: patch.ipv4Prefix,
        ipv6Prefix: patch.ipv6Prefix,
        exemptIps: patch.exemptIPs,
      },
    }),
  setClientAlias: (ip: string, name: string) =>
    request<void>("/api/v1/clients/alias", {
      method: "POST",
      body: { ip, name },
    }),

  // 加密 DNS
  encryptedStatus: () =>
    request<EncryptedDNSStatus>("/api/v1/encrypted/dns/status"),
  configureEncryptedDns: (patch: Record<string, unknown>) =>
    request<EncryptedDNSStatus>("/api/v1/encrypted/dns/configure", {
      method: "POST",
      body: patch,
    }),
  generateEncryptedCert: (patch: {
    keyType: string;
    commonName: string;
    dnsNames: string[];
    ipAddresses: string[];
    validDays: number;
    force: boolean;
  }) =>
    request<EncryptedDNSStatus>("/api/v1/encrypted/dns/cert/generate", {
      method: "POST",
      body: patch,
    }),
  importEncryptedCert: (patch: {
    mode: "pem" | "pkcs12";
    certPem?: string;
    keyPem?: string;
    data?: string;
    password?: string;
  }) =>
    request<EncryptedDNSStatus>("/api/v1/encrypted/dns/cert/import", {
      method: "POST",
      body: patch,
    }),
  configureEncryptedAcl: (patch: {
    enabled?: boolean;
    trustedSources?: string[];
    clientIpHeader?: string;
    confirmUnrestricted?: boolean;
  }) =>
    request<EncryptedDNSStatus>("/api/v1/encrypted/dns/acl", {
      method: "POST",
      body: patch,
    }),

  downloadMobileConfig: (protocol: "https" | "tls") =>
    downloadFile(
      `/api/v1/encrypted/mobileconfig?protocol=${protocol}`,
      `diting-${protocol}.mobileconfig`,
    ),
};

export function websocketUrl(token: string): string {
  const wsOrigin = window.location.origin
    .replace(/^http:/i, "ws:")
    .replace(/^https:/i, "wss:");
  return `${wsOrigin}/api/v1/events?token=${encodeURIComponent(token)}`;
}

async function downloadFile(path: string, filename: string): Promise<void> {
  const token = useAuthStore.getState().token;
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!response.ok) {
    const text = await response.text();
    throw new ApiError(text || `下载失败（HTTP ${response.status}）`, response.status);
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

export function describeError(error: unknown): string {
  if (error instanceof ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return "操作失败，请稍后重试。";
}
