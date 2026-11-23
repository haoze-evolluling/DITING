import { useState, type FormEvent } from "react";
import { AlertCircle, Eye, EyeOff, LockKeyhole, RefreshCw, ShieldCheck, UserRound } from "lucide-react";
import { m } from "motion/react";
import { Navigate, useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Skeleton } from "../components/ui/skeleton";
import { useAuthStatus } from "../hooks/use-api";
import { MOTION_EASE_OUT, useMotion } from "../hooks/use-motion";
import { api, describeError } from "../lib/api";
import { useAuthStore } from "../stores/auth";

const capabilities = [
  "解析、规则与日志全部留在本机",
  "一键接管系统 DNS，异常时自动还原",
  "实时查询流与 24 小时运行指标",
];

export function LoginPage() {
  const navigate = useNavigate();
  const authStatus = useAuthStatus();
  const token = useAuthStore((state) => state.token);
  const expired = useAuthStore((state) => state.isExpired());
  const setSession = useAuthStore((state) => state.setSession);
  const { allowPageEnter, isRich } = useMotion();

  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const initialized = authStatus.data?.initialized ?? false;
  const setupMode = authStatus.data ? !initialized : false;
  const locked = authStatus.data?.locked ?? false;
  const serviceAddress = window.location.origin;

  if (token && !expired) return <Navigate to="/" replace />;

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError("");
    if (!username.trim()) {
      setError("请输入管理员用户名。");
      return;
    }
    if (!password) {
      setError("请输入密码。");
      return;
    }
    if (setupMode && password !== confirm) {
      setError("两次输入的密码不一致。");
      return;
    }
    setBusy(true);
    try {
      if (setupMode) {
        await api.setup(username.trim(), password);
        toast.success("管理员账户已创建");
      }
      const session = await api.login(username.trim(), password);
      setSession(session);
      toast.success(setupMode ? "初始化完成，欢迎使用谛听" : "欢迎回来");
      navigate("/", { replace: true });
    } catch (cause) {
      setError(describeError(cause));
    } finally {
      setBusy(false);
    }
  };

  const retryConnection = () => {
    void authStatus.refetch();
  };

  return (
    <div className="grid h-full grid-cols-1 overflow-y-auto lg:grid-cols-[1.02fr_0.98fr]">
      <aside className="relative hidden overflow-hidden bg-[#08121f] px-12 py-10 text-white lg:flex lg:flex-col">
        <div
          aria-hidden
          className="motion-glow-ambient pointer-events-none absolute inset-0"
          style={{
            background:
              "radial-gradient(620px 420px at 18% 12%, rgba(47,123,246,0.28), transparent 62%), radial-gradient(520px 420px at 92% 88%, rgba(139,92,246,0.18), transparent 60%)",
          }}
        />
        <svg
          aria-hidden
          viewBox="0 0 420 420"
          className="motion-radar pointer-events-none absolute -right-24 top-1/3 h-[420px] w-[420px] text-white/[0.075]"
          fill="none"
          stroke="currentColor"
        >
          {[60, 110, 160, 210].map((radius) => (
            <circle key={radius} cx="210" cy="210" r={radius} strokeWidth="1" />
          ))}
          <path d="M210 0v420M0 210h420" strokeWidth="0.7" strokeDasharray="3 7" />
          <circle cx="210" cy="210" r="3" fill="currentColor" stroke="none" />
        </svg>

        <div className="relative flex items-center gap-3">
          <img src="/icon.webp" alt="谛听图标" className="h-10 w-10 rounded-xl ring-1 ring-white/15" />
          <div>
            <div className="text-[17px] font-semibold tracking-[-0.02em]">谛听 DITING</div>
            <div className="text-[10px] tracking-[0.24em] text-white/45">LOCAL DNS CONTROL</div>
          </div>
        </div>

        <div className="relative mt-auto max-w-[430px] pb-10">
          <h1 className="text-[40px] font-semibold leading-[1.15] tracking-[-0.045em] text-balance">
            解析在本机，
            <br />
            隐私不必外借。
          </h1>
          <p className="mt-4 max-w-[360px] text-[13.5px] leading-6 text-white/55">
            谛听把 DNS 过滤、缓存与查询日志全部留在你的设备上，桌面管理端只与本机服务通信。
          </p>
          <ul className="mt-8 space-y-3">
            {capabilities.map((item) => (
              <li key={item} className="flex items-center gap-2.5 text-[12.5px] text-white/70">
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-white/10 text-[#7fb3ff]">
                  <ShieldCheck className="h-3 w-3" />
                </span>
                {item}
              </li>
            ))}
          </ul>
          <div className="mt-10 flex items-center gap-3 text-[10.5px] tracking-[0.14em] text-white/35">
            <span className="h-px w-8 bg-white/20" />
            本地优先 · 无云端依赖
          </div>
        </div>
      </aside>

      <main className="app-canvas flex min-h-full items-center justify-center bg-bg px-5 py-10 sm:px-8">
        <m.div
          initial={allowPageEnter ? { opacity: 0, y: isRich ? 12 : 8 } : false}
          animate={{ opacity: 1, y: 0 }}
          transition={
            allowPageEnter
              ? { duration: isRich ? 0.34 : 0.24, ease: MOTION_EASE_OUT }
              : { duration: 0 }
          }
          className="w-full max-w-[384px]"
        >
          <div className="mb-8 flex items-center gap-2.5 lg:hidden">
            <img src="/icon.webp" alt="" className="h-9 w-9 rounded-xl ring-1 ring-border" />
            <div>
              <div className="text-[15px] font-semibold text-text">谛听 DITING</div>
              <div className="text-[10px] tracking-[0.2em] text-text-3">LOCAL DNS CONTROL</div>
            </div>
          </div>

          <h2 className="text-[24px] font-semibold tracking-[-0.03em] text-text">
            {setupMode ? "创建管理员账户" : "登录管理端"}
          </h2>
          <p className="mt-1.5 text-[12.5px] leading-5 text-text-3">
            {setupMode
              ? "首次使用需要设置管理凭据，用于保护 Web 管理页。"
              : "使用管理员凭据连接本机谛听桌面服务。"}
          </p>

          {authStatus.isLoading ? (
            <div className="mt-8 space-y-3">
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          ) : authStatus.isError ? (
            <div className="mt-7 rounded-xl border border-warn/30 bg-warn-soft p-3.5">
              <div className="flex items-center gap-2 text-[12.5px] font-medium text-warn">
                <AlertCircle className="h-4 w-4" />
                无法连接管理服务
              </div>
              <p className="mt-1.5 text-[11.5px] leading-5 text-warn/85">
                请确认 diting-service 正在运行。当前管理地址：
              </p>
              <p className="mono mt-1 break-all text-[11px] text-warn/80">{serviceAddress}</p>
              <Button
                size="sm"
                variant="ghost"
                className="mt-2 text-warn hover:bg-warn/10 hover:text-warn"
                onClick={retryConnection}
                loading={authStatus.isFetching}
              >
                <RefreshCw className="h-3.5 w-3.5" />
                重新连接
              </Button>
            </div>
          ) : (
            <form className="mt-7 space-y-4" onSubmit={submit}>
              <div>
                <label
                  htmlFor="login-username"
                  className="mb-1.5 block text-[12px] font-medium text-text-2"
                >
                  用户名
                </label>
                <Input
                  id="login-username"
                  value={username}
                  onChange={(event) => setUsername(event.target.value)}
                  autoComplete="username"
                  leading={<UserRound className="h-3.5 w-3.5" />}
                  placeholder="admin"
                />
              </div>

              <div>
                <label
                  htmlFor="login-password"
                  className="mb-1.5 block text-[12px] font-medium text-text-2"
                >
                  密码
                </label>
                <Input
                  id="login-password"
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  autoComplete={setupMode ? "new-password" : "current-password"}
                  leading={<LockKeyhole className="h-3.5 w-3.5" />}
                  trailing={
                    <button
                      type="button"
                      aria-label={showPassword ? "隐藏密码" : "显示密码"}
                      className="rounded p-0.5 hover:text-text-2"
                      onClick={() => setShowPassword((value) => !value)}
                    >
                      {showPassword ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                    </button>
                  }
                  placeholder={setupMode ? "至少 6 位" : "输入管理员密码"}
                />
              </div>

              {setupMode ? (
                <div>
                  <label
                    htmlFor="login-password-confirm"
                    className="mb-1.5 block text-[12px] font-medium text-text-2"
                  >
                    确认密码
                  </label>
                  <Input
                    id="login-password-confirm"
                    type={showPassword ? "text" : "password"}
                    value={confirm}
                    onChange={(event) => setConfirm(event.target.value)}
                    autoComplete="new-password"
                    leading={<LockKeyhole className="h-3.5 w-3.5" />}
                    placeholder="再次输入密码"
                  />
                </div>
              ) : null}

              {locked ? (
                <p className="rounded-lg bg-danger-soft px-3 py-2 text-[11.5px] text-danger">
                  尝试次数过多，请在 {authStatus.data?.lockoutRemainingSec ?? 0} 秒后重试。
                </p>
              ) : null}

              {error ? (
                <p className="flex items-start gap-1.5 rounded-lg bg-danger-soft px-3 py-2 text-[11.5px] leading-5 text-danger">
                  <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  {error}
                </p>
              ) : null}

              <Button
                type="submit"
                variant="primary"
                size="lg"
                className="w-full"
                loading={busy}
                disabled={locked}
              >
                {setupMode ? "创建并登录" : "登录"}
              </Button>
            </form>
          )}

          <div className="mt-8 flex items-center justify-between border-t border-border pt-4 text-[10.5px] text-text-3">
            <span className="truncate">服务地址 {serviceAddress || "同源"}</span>
            <span className="num">v{__APP_VERSION__}</span>
          </div>
        </m.div>
      </main>
    </div>
  );
}
