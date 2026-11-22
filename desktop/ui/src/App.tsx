import { lazy, useEffect } from "react";
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

  return (
    <ErrorBoundary>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<AppShell />}>
              <Route index element={<DashboardPage />} />
              <Route path="logs" element={<LogsPage />} />
              <Route path="filter" element={<FilterPage />} />
              <Route path="upstream" element={<UpstreamPage />} />
              <Route path="lan" element={<LanPage />} />
              <Route path="encrypted" element={<EncryptedPage />} />
              <Route path="settings" element={<SettingsPage />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
