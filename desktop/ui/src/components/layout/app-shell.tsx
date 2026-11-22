import { Suspense } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { Outlet } from "react-router-dom";

import { useStatus } from "../../hooks/use-api";
import { describeError } from "../../lib/api";
import { Button } from "../ui/button";
import { PageFallback } from "./page-fallback";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";

function ConnectionBanner() {
  const status = useStatus();
  if (!status.error) return null;
  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-warn/25 bg-warn-soft px-5 py-2 text-[12px] text-warn">
      <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
      <span className="min-w-0 flex-1">{describeError(status.error)}</span>
      <Button
        size="sm"
        variant="ghost"
        className="text-warn hover:bg-warn/10 hover:text-warn"
        onClick={() => void status.refetch()}
      >
        <RefreshCw className="h-3.5 w-3.5" />
        重试
      </Button>
    </div>
  );
}

export function AppShell() {
  return (
    <div className="flex h-full bg-bg">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <ConnectionBanner />
        <main className="app-canvas min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-[1480px] px-5 py-5 lg:px-7 lg:py-6">
            <Suspense fallback={<PageFallback />}>
              <Outlet />
            </Suspense>
          </div>
        </main>
      </div>
    </div>
  );
}
