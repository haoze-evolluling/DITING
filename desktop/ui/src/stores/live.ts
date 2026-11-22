import { create } from "zustand";

import type {
  MetricsStatus,
  QueryEvent,
  QueryRecord,
  StreamEvent,
} from "../lib/types";

const MAX_LIVE_QUERIES = 400;

interface LiveState {
  connected: boolean;
  metrics: MetricsStatus | null;
  queries: QueryRecord[];
  dnsState: string | null;
  takeoverState: unknown;
  setConnected: (connected: boolean) => void;
  applyEvent: (event: StreamEvent) => void;
  clearQueries: () => void;
  reset: () => void;
}

function toRecord(payload: QueryEvent, timestamp: number): QueryRecord {
  const status = payload.blocked
    ? "blocked"
    : payload.cacheHit
      ? "cached"
      : payload.success
        ? "allowed"
        : "error";
  return {
    ts: timestamp,
    domain: payload.domain,
    qtype: payload.qtype,
    clientIP: payload.clientIP,
    clientName: payload.clientName,
    durationMs: payload.durationMs,
    rcode: payload.rcode,
    status,
    cached: Boolean(payload.cacheHit),
    cacheHit: payload.cacheHit,
    blocked: payload.blocked,
    filterRule: payload.filterRule,
    filterReason: payload.filterReason,
    error: payload.errorMessage,
  };
}

export const useLiveStore = create<LiveState>()((set) => ({
  connected: false,
  metrics: null,
  queries: [],
  dnsState: null,
  takeoverState: null,
  setConnected: (connected) => set({ connected }),
  applyEvent: (event) => {
    if (event.type === "metrics") {
      set({ metrics: event.data as MetricsStatus });
      return;
    }
    if (event.type === "query") {
      const record = toRecord(event.data as QueryEvent, event.timestamp || Date.now());
      set((state) => ({
        queries: [record, ...state.queries].slice(0, MAX_LIVE_QUERIES),
      }));
      return;
    }
    if (event.type === "dns") {
      set({ dnsState: String(event.data ?? "") });
      return;
    }
    if (event.type === "takeover") {
      set({ takeoverState: event.data });
    }
  },
  clearQueries: () => set({ queries: [] }),
  reset: () =>
    set({
      connected: false,
      metrics: null,
      queries: [],
      dnsState: null,
      takeoverState: null,
    }),
}));
