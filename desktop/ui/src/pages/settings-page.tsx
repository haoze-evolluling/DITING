import { ArrowRight, Copy, Info, LogOut, Server } from "lucide-react";
import { Link } from "react-router-dom";

import { PageHeader } from "../components/layout/page-header";
import { AppearanceCard } from "../components/settings/appearance-card";
import { BackupCard } from "../components/settings/backup-card";
import { LoginBackgroundCard } from "../components/settings/login-background-card";
import { PasswordCard } from "../components/settings/password-card";
import { QueryLogCard } from "../components/settings/query-log-card";
import { ServiceCard } from "../components/settings/service-card";
import { WebAccessCard } from "../components/settings/web-access-card";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../components/ui/card";
import { InfoRow } from "../components/ui/info-row";
import { useMeta, useStatus } from "../hooks/use-api";
import { useLogout } from "../hooks/use-logout";
import { copyText } from "../lib/clipboard";
import { formatUnixSeconds } from "../lib/format";
import { useAuthStore } from "../stores/auth";

function AccountCard() {
  const username = useAuthStore((state) => state.username);
  const expiresAt = useAuthStore((state) => state.expiresAt);
  const logout = useLogout();

  return (
    <Card className="flex flex-col">
      <CardHeader title="账户与连接" description="当前管理凭据和桌面服务地址。" />
      <CardContent className="flex-1 pt-1">
        <InfoRow label="管理员">{username ?? "admin"}</InfoRow>
        <InfoRow label="会话到期">{formatUnixSeconds(expiresAt ?? 0)}</InfoRow>
        <InfoRow label="管理服务" mono>
          {window.location.origin}
        </InfoRow>
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">退出后需要重新输入管理员密码</span>
        <Button size="sm" variant="dangerSoft" onClick={() => void logout()}>
          <LogOut className="h-3.5 w-3.5" />
          退出登录
        </Button>
      </CardFooter>
    </Card>
  );
}

function AboutCard() {
  const status = useStatus();
  const meta = useMeta();

  return (
    <Card>
      <CardHeader
        title="关于"
        description="谛听桌面端与本地优先设计。"
        actions={<Info className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="pt-2">
        <div className="flex items-center gap-3">
          <img src="/icon.webp" alt="" className="h-11 w-11 rounded-xl ring-1 ring-border" />
          <div>
            <div className="text-[14px] font-semibold text-text">谛听 DITING</div>
            <div className="text-[10.5px] text-text-3">
              桌面管理端 v{__APP_VERSION__} · 服务 v{status.data?.version ?? "—"}
            </div>
          </div>
        </div>
        <p className="mt-3 text-[11.5px] leading-5 text-text-3">
          解析、规则、缓存与查询日志均在本机完成。桌面管理端只通过回环地址与本机服务通信，不依赖云端账户。
        </p>
        <div className="mt-3">
          <InfoRow label="开源地址" mono>
            <button
              type="button"
              onClick={() => copyText("https://github.com/haoze-evolluling/DITING", "地址")}
              className="inline-flex max-w-full items-center gap-1 break-all text-right hover:text-text"
            >
              github.com/haoze-evolluling/DITING
              <Copy className="h-3 w-3" />
            </button>
          </InfoRow>
          <InfoRow label="许可证">GNU General Public License v3.0</InfoRow>
          <InfoRow label="数据库位置" mono>
            {meta.data?.databasePath ?? "—"}
          </InfoRow>
        </div>
      </CardContent>
    </Card>
  );
}

export function SettingsPage() {
  return (
    <>
      <PageHeader title="设置" description="外观、日志、桌面服务与连接信息" />
      <div className="card-grid-2">
        <AppearanceCard />
        <AccountCard />
        <QueryLogCard />
        <ServiceCard />
        <WebAccessCard />
        <LoginBackgroundCard />
        <BackupCard />
        <Card className="flex flex-col">
          <CardHeader
            title="管理模块"
            description="控制面已覆盖解析、缓存、防护、重写、局域网与加密解析。"
            actions={<Server className="h-4 w-4 text-text-3" />}
          />
          <CardContent className="flex-1 space-y-1 pt-2">
            {[
              { to: "/upstream", label: "上游解析", hint: "调度策略、上游服务器与 Bootstrap" },
              { to: "/cache", label: "解析缓存", hint: "命中统计、缓存策略与落盘恢复" },
              { to: "/filter", label: "规则与拦截", hint: "订阅源、自定义规则、服务与时间计划" },
              { to: "/safety", label: "安全搜索与浏览", hint: "安全搜索、威胁情报与家长控制" },
              { to: "/advanced", label: "DNS 高级与隐私", hint: "协议加固、Hosts、ECS 与 DNS64" },
              { to: "/rewrite", label: "重写与区文件", hint: "域名改写、自定义记录与内网区" },
              { to: "/lan", label: "局域网与客户端", hint: "对外 53 端口、访问控制、限速与分组" },
              { to: "/encrypted", label: "加密 DNS", hint: "DoT / DoH、证书与反向代理来源" },
            ].map((item) => (
              <Link
                key={item.to}
                to={item.to}
                className="group flex items-center justify-between gap-3 rounded-xl border border-border bg-surface-2 px-3 py-2.5 transition-colors hover:border-border-strong hover:bg-surface-3"
              >
                <span className="min-w-0">
                  <span className="block text-[12px] font-medium text-text">{item.label}</span>
                  <span className="mt-0.5 block truncate text-[10.5px] text-text-3">
                    {item.hint}
                  </span>
                </span>
                <ArrowRight className="h-3.5 w-3.5 shrink-0 text-text-3 transition-transform duration-150 group-hover:translate-x-0.5 group-hover:text-text-2" />
              </Link>
            ))}
          </CardContent>
        </Card>
        <PasswordCard />
        <AboutCard />
      </div>
    </>
  );
}
