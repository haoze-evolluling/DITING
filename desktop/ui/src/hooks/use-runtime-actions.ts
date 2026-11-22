import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { api, describeError } from "../lib/api";
import { useLiveStore } from "../stores/live";

function useInvalidateRuntime() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["status"] }),
      queryClient.invalidateQueries({ queryKey: ["service-status"] }),
      queryClient.invalidateQueries({ queryKey: ["adapters"] }),
    ]);
}

export function useRuntimeActions() {
  const invalidate = useInvalidateRuntime();
  const queryClient = useQueryClient();

  const startDns = useMutation({
    mutationFn: api.startDns,
    onSuccess: () => toast.success("DNS 服务已启动"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const stopDns = useMutation({
    mutationFn: api.stopDns,
    onSuccess: () => toast.success("DNS 服务已停止"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const enableTakeover = useMutation({
    mutationFn: api.enableTakeover,
    onSuccess: () => toast.success("系统 DNS 已接管"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const disableTakeover = useMutation({
    mutationFn: api.disableTakeover,
    onSuccess: () => toast.success("系统 DNS 已还原"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const setAdapterTakeover = useMutation({
    mutationFn: (input: { adapterId: string; enable: boolean }) =>
      api.setAdapterTakeover(input.adapterId, input.enable),
    onSuccess: () => toast.success("网卡接管状态已更新"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const emergencyRestore = useMutation({
    mutationFn: api.emergencyRestore,
    onSuccess: (result) => {
      if (result.healed) {
        toast.success(result.message || "系统 DNS 已紧急恢复");
      } else {
        toast.info(result.message || "没有检测到残留的 DNS 配置");
      }
    },
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  const clearQueryLog = useMutation({
    mutationFn: api.clearQueryLog,
    onSuccess: () => {
      useLiveStore.getState().clearQueries();
      void queryClient.invalidateQueries({ queryKey: ["query-stats"] });
      void queryClient.invalidateQueries({ queryKey: ["query-search"] });
      toast.success("查询日志与统计已清空");
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const portAutofix = useMutation({
    mutationFn: (startDns: boolean) => api.portAutofix(startDns),
    onSuccess: () => toast.success("端口冲突已处理"),
    onError: (error) => toast.error(describeError(error)),
    onSettled: invalidate,
  });

  return {
    startDns,
    stopDns,
    enableTakeover,
    disableTakeover,
    setAdapterTakeover,
    emergencyRestore,
    clearQueryLog,
    portAutofix,
  };
}
