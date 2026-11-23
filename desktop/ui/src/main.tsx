import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "sonner";

import App from "./App";
import { TooltipProvider } from "./components/ui/tooltip";
import { useIsDark } from "./hooks/use-theme";
import "./styles.css";

function AppToaster() {
  const dark = useIsDark();
  return (
    <Toaster
      position="bottom-right"
      theme={dark ? "dark" : "light"}
      closeButton
      toastOptions={{ className: "text-[12.5px]" }}
    />
  );
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
      staleTime: 2_000,
    },
  },
});

const root = document.getElementById("root");
if (!root) throw new Error("缺少 #root 挂载节点");

createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <TooltipProvider delayDuration={220}>
        <App />
        <AppToaster />
      </TooltipProvider>
    </QueryClientProvider>
  </StrictMode>,
);
