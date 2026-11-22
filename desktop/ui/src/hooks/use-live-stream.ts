import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { websocketUrl } from "../lib/api";
import type { StreamEvent } from "../lib/types";
import { useAuthStore } from "../stores/auth";
import { useLiveStore } from "../stores/live";

const MAX_BACKOFF_MS = 15_000;

export function useLiveStream(): void {
  const token = useAuthStore((state) => state.token);
  const queryClient = useQueryClient();

  useEffect(() => {
    const reset = useLiveStore.getState().reset;
    if (!token) {
      reset();
      return;
    }

    let socket: WebSocket | null = null;
    let retryTimer: number | undefined;
    let attempt = 0;
    let stopped = false;

    const schedule = () => {
      if (stopped) return;
      const delay = Math.min(1000 * 2 ** attempt, MAX_BACKOFF_MS);
      attempt += 1;
      retryTimer = window.setTimeout(connect, delay);
    };

    const connect = () => {
      if (stopped) return;
      try {
        socket = new WebSocket(websocketUrl(token));
      } catch {
        schedule();
        return;
      }

      socket.onopen = () => {
        if (stopped) return;
        attempt = 0;
        useLiveStore.getState().setConnected(true);
        queryClient.invalidateQueries({ queryKey: ["status"] });
        queryClient.invalidateQueries({ queryKey: ["query-stats"] });
      };

      socket.onmessage = (message) => {
        let event: StreamEvent;
        try {
          event = JSON.parse(String(message.data)) as StreamEvent;
        } catch {
          return;
        }
        useLiveStore.getState().applyEvent(event);
        if (event.type === "dns" || event.type === "takeover") {
          queryClient.invalidateQueries({ queryKey: ["status"] });
          queryClient.invalidateQueries({ queryKey: ["service-status"] });
          queryClient.invalidateQueries({ queryKey: ["adapters"] });
        }
      };

      socket.onerror = () => {
        socket?.close();
      };

      socket.onclose = () => {
        if (stopped) return;
        useLiveStore.getState().setConnected(false);
        socket = null;
        schedule();
      };
    };

    connect();

    return () => {
      stopped = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      if (socket) {
        socket.onclose = null;
        socket.close();
      }
      useLiveStore.getState().setConnected(false);
    };
  }, [token, queryClient]);
}
