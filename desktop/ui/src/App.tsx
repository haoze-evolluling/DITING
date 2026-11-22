import { lazy, useEffect } from "react";
import {
  BrowserRouter,
  HashRouter,
  Navigate,
  Outlet,
  Route,
  Routes,
} from "react-router-dom";

import { ErrorBoundary } from "./components/error-boundary";
import { AppShell } from "./components/layout/app-shell";
import { useLiveStream } from "./hooks/use-live-stream";
import { useApplyTheme } from "./hooks/use-theme";
import { isTauri } from "./lib/api";
import { LoginPage } from "./pages/login-page";
import { useAuthStore } from "./stores/auth";

const DashboardPage = lazy(async () => ({
  default: (await import("./pages/dashboard-page")).DashboardPage,
}));
const LogsPage = lazy(async () => ({
  default: (await import("./pages/logs-page")).LogsPage,
}));
const SettingsPage = lazy(async () => ({
  default: (await import("./pages/settings-page")).SettingsPage,
}));

const Router = isTauri ? HashRouter : BrowserRouter;

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
      <Router>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<AppShell />}>
              <Route index element={<DashboardPage />} />
              <Route path="logs" element={<LogsPage />} />
              <Route path="settings" element={<SettingsPage />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Router>
    </ErrorBoundary>
  );
}
