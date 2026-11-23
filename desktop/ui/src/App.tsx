import { lazy, useEffect } from "react";
import { LazyMotion, MotionConfig, domMax } from "motion/react";
import {
  BrowserRouter,
  Navigate,
  Outlet,
  Route,
  Routes,
} from "react-router-dom";

import { ErrorBoundary } from "./components/error-boundary";
import { AppShell } from "./components/layout/app-shell";
import { useLiveStream } from "./hooks/use-live-stream";
import { useMotion } from "./hooks/use-motion";
import { useApplyTheme } from "./hooks/use-theme";
import { LoginPage } from "./pages/login-page";
import { useAuthStore } from "./stores/auth";

const DashboardPage = lazy(async () => ({
  default: (await import("./pages/dashboard-page")).DashboardPage,
}));
const LogsPage = lazy(async () => ({
  default: (await import("./pages/logs-page")).LogsPage,
}));
const FilterPage = lazy(async () => ({
  default: (await import("./pages/filter-page")).FilterPage,
}));
const UpstreamPage = lazy(async () => ({
  default: (await import("./pages/upstream-page")).UpstreamPage,
}));
const CachePage = lazy(async () => ({
  default: (await import("./pages/cache-page")).CachePage,
}));
const SafetyPage = lazy(async () => ({
  default: (await import("./pages/safety-page")).SafetyPage,
}));
const AdvancedPage = lazy(async () => ({
  default: (await import("./pages/advanced-page")).AdvancedPage,
}));
const RewritePage = lazy(async () => ({
  default: (await import("./pages/rewrite-page")).RewritePage,
}));
const LanPage = lazy(async () => ({
  default: (await import("./pages/lan-page")).LanPage,
}));
const EncryptedPage = lazy(async () => ({
  default: (await import("./pages/encrypted-page")).EncryptedPage,
}));
const SettingsPage = lazy(async () => ({
  default: (await import("./pages/settings-page")).SettingsPage,
}));

function ProtectedRoute() {
  const token = useAuthStore((state) => state.token);
  const clear = useAuthStore((state) => state.clear);
  const expired = useAuthStore((state) => state.isExpired());

  useLiveStream();

  useEffect(() => {
    if (token && expired) clear();
  }, [token, expired, clear]);

  if (!token || expired) {
    return <Navigate to="/login" replace />;
  }
  return <Outlet />;
}

export default function App() {
  useApplyTheme();
  const { isOff } = useMotion();

  return (
    <ErrorBoundary>
      <LazyMotion features={domMax} strict>
        <MotionConfig reducedMotion={isOff ? "always" : "never"}>
          <BrowserRouter>
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route element={<ProtectedRoute />}>
                <Route element={<AppShell />}>
                  <Route index element={<DashboardPage />} />
                  <Route path="logs" element={<LogsPage />} />
                  <Route path="cache" element={<CachePage />} />
                  <Route path="filter" element={<FilterPage />} />
                  <Route path="safety" element={<SafetyPage />} />
                  <Route path="advanced" element={<AdvancedPage />} />
                  <Route path="upstream" element={<UpstreamPage />} />
                  <Route path="rewrite" element={<RewritePage />} />
                  <Route path="lan" element={<LanPage />} />
                  <Route path="encrypted" element={<EncryptedPage />} />
                  <Route path="settings" element={<SettingsPage />} />
                </Route>
              </Route>
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </BrowserRouter>
        </MotionConfig>
      </LazyMotion>
    </ErrorBoundary>
  );
}
