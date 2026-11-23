import { useEffect, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowRight,
  Copy,
  Database,
  Info,
  LogOut,
  RefreshCw,
  Save,
  Server,
  ShieldAlert,
} from "lucide-react";
import { Link } from "react-router-dom";
import { toast } from "sonner";

import { PageHeader } from "../components/layout/page-header";
import { AppearanceCard } from "../components/settings/appearance-card";
import { PasswordCard } from "../components/settings/password-card";
import { WebAccessCard } from "../components/settings/web-access-card";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../components/ui/card";
import { Input } from "../components/ui/input";
import { Skeleton } from "../components/ui/skeleton";
import { Switch } from "../components/ui/switch";
import { useQueryLogConfig, useServiceStatus, useStatus } from "../hooks/use-api";
import { useLogout } from "../hooks/use-logout";
import { api, describeError } from "../lib/api";
import { formatNumber, formatUptime, formatUnixSeconds } from "../lib/format";
import {
  autoStartMechanismLabel,
  platformLabel,
  serviceStateLabel,
} from "../lib/labels";
import type { QueryLogConfig } from "../lib/types";
import { useAuthStore } from "../stores/auth";

function InfoRow({
  label,
  children,
  mono = false,
}: {
  label: string;
  children: ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex min-w-0 items-start justify-between gap-4 border-b border-border/60 py-2 last:border-b-0">
      <span className="shrink-0 text-[11.5px] text-text-3">{label}</span>
      <span
        className={
          mono
            ? "mono min-w-0 break-all text-right text-[11px] text-text-2"
            : "min-w-0 break-words text-right text-[12px] text-text-2"
        }
      >
        {children}
      </span>
    </div>
  );
}

function copyText(value: string, label: string) {
  navigator.clipboard
    .writeText(value)
    .then(() => toast.success(`${label}已复制`))
    .catch(() => toast.error("无法访问剪贴板"));
}

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
        <span className="text-[10.5px] text-text-3">
          退出后需要重新输入管理员密码
        </span>
        <Button size="sm" variant="dangerSoft" onClick={() => void logout()}>
          <LogOut className="h-3.5 w-3.5" />
          退出登录
        </Button>
      </CardFooter>
    </Card>
  );
}

function QueryLogCard() {
  const config = useQueryLogConfig();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<QueryLogConfig | null>(null);

  useEffect(() => {
    if (config.data) setDraft(config.data);
  }, [config.data]);

  const save = useMutation({
    mutationFn: (value: QueryLogConfig) =>
      api.updateQueryConfig({
        enabled: value.enabled,
        fileEnabled: value.fileEnabled,
        logClients: value.logClients,
        maxEntries: value.maxEntries,
        retentionDays: value.retentionDays,
      }),
    onSuccess: () => {
      toast.success("查询日志配置已更新");
      void queryClient.invalidateQueries({ queryKey: ["query-config"] });
      void queryClient.invalidateQueries({ queryKey: ["query-stats"] });
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const update = (patch: Partial<QueryLogConfig>) =>
    setDraft((current) => (current ? { ...current, ...patch } : current));

  const valid =
    draft &&
    draft.maxEntries >= 100 &&
    draft.maxEntries <= 200_000 &&
    draft.retentionDays >= 1 &&
    draft.retentionDays <= 365;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="查询日志"
        description="控制内存日志容量、落盘与保留周期。"
        actions={<Database className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex-1 pt-2">
        {config.isLoading || !draft ? (
          <div className="space-y-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
        ) : (
          <div className="space-y-1">
            <div className="flex items-center justify-between gap-4 border-b border-border/60 py-2">
              <div>
                <div className="text-[12px] text-text">记录查询日志</div>
                <div className="text-[10.5px] text-text-3">关闭后不再记录新的解析请求</div>
              </div>
              <Switch
                checked={draft.enabled}
                onCheckedChange={(value) => update({ enabled: value })}
                label="记录查询日志"
              />
            </div>
            <div className="flex items-center justify-between gap-4 border-b border-border/60 py-2">
              <div>
                <div className="text-[12px] text-text">写入按日文件</div>
                <div className="text-[10.5px] text-text-3">querylog-YYYYMMDD.jsonl</div>
              </div>
              <Switch
                checked={draft.fileEnabled}
                onCheckedChange={(value) => update({ fileEnabled: value })}
                label="写入按日文件"
              />
            </div>
            <div className="flex items-center justify-between gap-4 border-b border-border/60 py-2">
              <div>
                <div className="text-[12px] text-text">记录客户端地址</div>
                <div className="text-[10.5px] text-text-3">用于客户端排名与访问排查</div>
              </div>
              <Switch
                checked={draft.logClients}
                onCheckedChange={(value) => update({ logClients: value })}
                label="记录客户端地址"
              />
            </div>
            <div className="grid gap-3 border-b border-border/60 py-2 sm:grid-cols-2">
              <label className="block">
                <span className="text-[12px] text-text">内存最大条目</span>
                <Input
                  className="mt-1.5"
                  type="number"
                  min={100}
                  max={200000}
                  value={draft.maxEntries}
                  onChange={(event) => update({ maxEntries: Number(event.target.value) })}
                />
                <span className="mt-1 block text-[10.5px] text-text-3">
                  100 – 200,000 条，当前 {formatNumber(draft.maxEntries)}
                </span>
              </label>
              <label className="block">
                <span className="text-[12px] text-text">保留天数</span>
                <Input
                  className="mt-1.5"
                  type="number"
                  min={1}
                  max={365}
                  value={draft.retentionDays}
                  onChange={(event) => update({ retentionDays: Number(event.target.value) })}
                />
                <span className="mt-1 block text-[10.5px] text-text-3">
                  1 – 365 天，当前 {draft.retentionDays} 天
                </span>
              </label>
            </div>
            <div className="py-2">
              <div className="text-[11px] text-text-3">落盘目录</div>
              <div className="mt-1.5 flex items-center gap-2 rounded-lg bg-surface-2 px-2.5 py-1.5">
                <span className="mono min-w-0 flex-1 truncate text-[10.5px] text-text-2" title={draft.dataDir}>
                  {draft.dataDir}
                </span>
                <button
                  type="button"
                  onClick={() => copyText(draft.dataDir, "目录")}
                  className="shrink-0 rounded p-0.5 text-text-3 hover:text-text"
                  title="复制目录"
                  aria-label="复制落盘目录"
                >
                  <Copy className="h-3 w-3" />
                </button>
              </div>
            </div>
            {!valid ? (
              <p className="rounded-lg bg-warn-soft px-3 py-2 text-[11px] text-warn">
                容量或保留天数超出允许范围，修正后才能保存。
              </p>
            ) : null}
          </div>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">保存后立即在服务端生效</span>
        <Button
          size="sm"
          variant="primary"
          disabled={!draft || !valid}
          loading={save.isPending}
          onClick={() => draft && save.mutate(draft)}
        >
          <Save className="h-3.5 w-3.5" />
          保存
        </Button>
      </CardFooter>
    </Card>
  );
}

function ServiceCard() {
  const service = useServiceStatus();
  const status = useStatus();
  const meta = useQuery({ queryKey: ["meta"], queryFn: api.meta, retry: 1 });
  const data = service.data;

  return (
    <Card>
      <CardHeader
        title="桌面服务"
        description="系统级 DNS 服务的安装、权限与运行信息。"
        actions={
          <Button size="sm" variant="ghost" onClick={() => void service.refetch()}>
            <RefreshCw className="h-3.5 w-3.5" />
            刷新
          </Button>
        }
      />
      <CardContent className="pt-1">
        {service.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-7 w-full" />
            <Skeleton className="h-7 w-full" />
          </div>
        ) : data ? (
          <>
            <InfoRow label="服务状态">
              <span className="flex items-center justify-end gap-2">
                <Badge tone={data.running ? "good" : "warn"} dot>
                  {serviceStateLabel(data.state, data.stateText)}
                </Badge>
                <span className="text-[10.5px] text-text-3">{data.installed ? "已安装" : "未安装"}</span>
              </span>
            </InfoRow>
            <InfoRow label="运行权限">
              <Badge tone={data.isElevated ? "good" : "warn"}>
                {data.isElevated ? "管理员权限" : "普通权限"}
              </Badge>
            </InfoRow>
            <InfoRow label="开机自启">
              {data.autoStart?.enabled ? "已启用" : "未启用"}
              {data.autoStart?.mechanism ? (
                <span className="ml-1 text-[10.5px] text-text-3">
                  {autoStartMechanismLabel(data.autoStart.mechanism)}
                </span>
              ) : null}
            </InfoRow>
            <InfoRow label="后端版本">{status.data ? `v${status.data.version}` : "—"}</InfoRow>
            <InfoRow label="进程">{status.data ? `PID ${status.data.pid} · 运行 ${formatUptime(status.data.uptimeSeconds)}` : "—"}</InfoRow>
            <InfoRow label="平台">{platformLabel(meta.data?.os)}</InfoRow>
            <InfoRow label="可执行文件" mono>
              {data.executablePath || "—"}
            </InfoRow>
            {data.message ? (
              <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[11px] leading-5 text-text-3">
                {data.message}
              </p>
            ) : null}
            {!data.isElevated ? (
              <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-warn-soft px-3 py-2 text-[11px] leading-5 text-warn">
                <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                系统 DNS 接管需要管理员权限。请安装为系统服务，或以管理员身份启动 diting-service。
              </p>
            ) : null}
          </>
        ) : (
          <p className="py-3 text-[11.5px] text-text-3">
            {describeError(service.error)}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

function AboutCard() {
  const status = useStatus();
  const config = useQueryLogConfig();

  return (
    <Card>
      <CardHeader title="关于" description="谛听桌面端与本地优先设计。" actions={<Info className="h-4 w-4 text-text-3" />} />
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
          <InfoRow label="数据目录" mono>
            {config.data?.dataDir ?? "—"}
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
