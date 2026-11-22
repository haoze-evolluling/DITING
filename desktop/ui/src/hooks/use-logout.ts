import { useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";

import { api } from "../lib/api";
import { useAuthStore } from "../stores/auth";
import { useLiveStore } from "../stores/live";

export function useLogout(): () => Promise<void> {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  return async () => {
    try {
      await api.logout();
    } catch {
      // A stale session is cleared locally regardless of the server response.
    }
    useAuthStore.getState().clear();
    useLiveStore.getState().reset();
    queryClient.clear();
    navigate("/login", { replace: true });
  };
}
