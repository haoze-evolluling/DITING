import {
  keepPreviousData,
  useQuery,
  type UseQueryResult,
} from "@tanstack/react-query";

import { api } from "../lib/api";
import type {
  AdapterInfo,
  AuthStatus,
  BlockedServicesResponse,
  EncryptedDNSStatus,
  FilterConfig,
  FilterListsResponse,
  FilterPauseResponse,
  FilterRulesResponse,
  LanStatus,
  QueryLogConfig,
  QueryLogStats,
  QuerySearchParams,
  QuerySearchResult,
  ResolverConfig,
  ScheduleConfigResponse,
  ServiceStatus,
  StatusResponse,
} from "../lib/types";
import { useAuthStore } from "../stores/auth";

export function useAuthStatus(): UseQueryResult<AuthStatus> {
  return useQuery({
    queryKey: ["auth-status"],
    queryFn: api.authStatus,
    retry: 1,
    refetchInterval: 30_000,
  });
}

export function useStatus(): UseQueryResult<StatusResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["status"],
    queryFn: api.status,
    enabled: Boolean(token),
    refetchInterval: 5_000,
    retry: 1,
  });
}

export function useServiceStatus(): UseQueryResult<ServiceStatus> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["service-status"],
    queryFn: api.serviceStatus,
    enabled: Boolean(token),
    refetchInterval: 30_000,
    retry: 1,
  });
}

export function useAdapters(enabled = true): UseQueryResult<AdapterInfo[]> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["adapters"],
    queryFn: api.adapters,
    enabled: Boolean(token) && enabled,
    refetchInterval: 20_000,
    retry: 1,
  });
}

export function useQueryStats(): UseQueryResult<QueryLogStats> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["query-stats"],
    queryFn: api.queryStats,
    enabled: Boolean(token),
    refetchInterval: 15_000,
    retry: 1,
  });
}

export function useQueryLogConfig(): UseQueryResult<QueryLogConfig> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["query-config"],
    queryFn: api.queryConfig,
    enabled: Boolean(token),
    retry: 1,
  });
}

export function useQueryLogSearch(
  params: QuerySearchParams,
  enabled = true,
): UseQueryResult<QuerySearchResult> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["query-search", params],
    queryFn: () => api.querySearch(params),
    enabled: Boolean(token) && enabled,
    placeholderData: keepPreviousData,
    retry: 1,
    refetchOnWindowFocus: false,
  });
}

export function useUpstreamConfig(): UseQueryResult<ResolverConfig> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["upstream-config"],
    queryFn: api.upstreamConfig,
    enabled: Boolean(token),
    refetchInterval: 30_000,
    retry: 1,
  });
}

export function useFilterConfig(): UseQueryResult<FilterConfig> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["filter-config"],
    queryFn: api.filterConfig,
    enabled: Boolean(token),
    retry: 1,
  });
}

export function useFilterLists(): UseQueryResult<FilterListsResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["filter-lists"],
    queryFn: api.filterLists,
    enabled: Boolean(token),
    refetchInterval: 30_000,
    retry: 1,
  });
}

export function useCustomRules(): UseQueryResult<FilterRulesResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["filter-rules"],
    queryFn: api.customRules,
    enabled: Boolean(token),
    retry: 1,
  });
}

export function useFilterSchedule(): UseQueryResult<ScheduleConfigResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["filter-schedule"],
    queryFn: api.filterSchedule,
    enabled: Boolean(token),
    refetchInterval: 60_000,
    retry: 1,
  });
}

export function useFilterPause(): UseQueryResult<FilterPauseResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["filter-pause"],
    queryFn: api.filterPause,
    enabled: Boolean(token),
    refetchInterval: 15_000,
    retry: 1,
  });
}

export function useBlockedServices(): UseQueryResult<BlockedServicesResponse> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["blocked-services"],
    queryFn: api.blockedServices,
    enabled: Boolean(token),
    retry: 1,
  });
}

export function useLanStatus(): UseQueryResult<LanStatus> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["lan-status"],
    queryFn: api.lanStatus,
    enabled: Boolean(token),
    refetchInterval: 30_000,
    retry: 1,
  });
}

export function useEncryptedStatus(): UseQueryResult<EncryptedDNSStatus> {
  const token = useAuthStore((state) => state.token);
  return useQuery({
    queryKey: ["encrypted-status"],
    queryFn: api.encryptedStatus,
    enabled: Boolean(token),
    refetchInterval: 60_000,
    retry: 1,
  });
}
