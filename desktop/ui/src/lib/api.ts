import { useAuthStore } from "../stores/auth";

import type {
  AdapterInfo,
  ApiEnvelope,
  AuthStatus,
  EmergencyRestoreResult,
  LoginResult,
  MetaInfo,
  PortCheckResult,
  QueryLogConfig,
  QueryLogStats,
  QuerySearchParams,
  QuerySearchResult,
  ServiceStatus,
  StatusResponse,
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
};

export function websocketUrl(token: string): string {
  const wsOrigin = window.location.origin
    .replace(/^http:/i, "ws:")
    .replace(/^https:/i, "wss:");
  return `${wsOrigin}/api/v1/events?token=${encodeURIComponent(token)}`;
}

export function describeError(error: unknown): string {
  if (error instanceof ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return "操作失败，请稍后重试。";
}
