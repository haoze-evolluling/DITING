import { RefreshCw, ShieldAlert, Terminal } from "lucide-react";

import { useMeta, useServiceStatus, useStatus } from "../../hooks/use-api";
import { describeError } from "../../lib/api";
import { formatUptime } from "../../lib/format";
import {
  autoStartMechanismLabel,
  platformLabel,
  serviceStateLabel,
} from "../../lib/labels";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardHeader } from "../ui/card";
import { InfoRow } from "../ui/info-row";
import { LoadingState } from "../ui/loading";

export function ServiceCard() {
  const service = useServiceStatus();
  const status = useStatus();
  const meta = useMeta();
  const data = service.data;
  const isOpenWrt = meta.data?.platformKind === "openwrt";

  return (
    <>
      <Card className="flex flex-col">
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
        <CardContent className="flex-1 pt-1">
          {service.isLoading ? (
            <LoadingState label="正在加载服务信息…" />
          ) : data ? (
            <>
              <InfoRow label="服务状态">
                <span className="flex items-center justify-end gap-2">
                  <Badge tone={data.running ? "good" : "warn"} dot>
                    {serviceStateLabel(data.state, data.stateText)}
                  </Badge>
                  <span className="text-[10.5px] text-text-3">
                    {data.installed ? "已安装" : "未安装"}
                  </span>
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
              <InfoRow label="后端版本">
                {status.data ? `v${status.data.version}` : "—"}
              </InfoRow>
              <InfoRow label="进程">
                {status.data
                  ? `PID ${status.data.pid} · 运行 ${formatUptime(status.data.uptimeSeconds)}`
                  : "—"}
              </InfoRow>
            </>
          ) : (
            <p className="py-3 text-[11.5px] text-text-3">{describeError(service.error)}</p>
          )}
        </CardContent>
      </Card>

      <Card className="flex flex-col">
        <CardHeader
          title="运行环境"
          description="可执行文件、平台与服务端运行提示。"
          actions={<Terminal className="h-4 w-4 text-text-3" />}
        />
        <CardContent className="flex-1 pt-1">
          {service.isLoading ? (
            <LoadingState label="正在加载运行环境…" />
          ) : data ? (
            <>
              <InfoRow label="平台">
                {platformLabel(
                  meta.data?.os,
                  meta.data?.distro,
                  meta.data?.platformKind,
                )}
              </InfoRow>
              <InfoRow label="可执行文件" mono>
                {data.executablePath || "—"}
              </InfoRow>
              {data.message ? (
                <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[11px] leading-5 text-text-3">
                  {data.message}
                </p>
              ) : null}
              {isOpenWrt ? (
                <p className="mt-2 rounded-lg bg-surface-2 px-3 py-2 text-[10.5px] leading-5 text-text-3">
                  若忘记管理员密码，可通过路由器 SSH 执行{" "}
                  <span className="mono text-text-2">
                    diting-service -reset-password &lt;新密码&gt;
                  </span>{" "}
                  重置。
                </p>
              ) : null}
              {!data.isElevated ? (
                <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-warn-soft px-3 py-2 text-[11px] leading-5 text-warn">
                  <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  系统 DNS 接管需要管理员权限。请安装为系统服务，或以管理员身份启动
                  diting-service。
                </p>
              ) : null}
            </>
          ) : (
            <p className="py-3 text-[11.5px] text-text-3">无法读取运行环境信息。</p>
          )}
        </CardContent>
      </Card>
    </>
  );
}
