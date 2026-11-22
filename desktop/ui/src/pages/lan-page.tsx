import { AccessControlCard } from "../components/lan/access-control-card";
import { ClientsCard } from "../components/lan/clients-card";
import { LanServiceCard } from "../components/lan/lan-service-card";
import { RateLimitCard } from "../components/lan/rate-limit-card";
import { PageHeader } from "../components/layout/page-header";

export function LanPage() {
  return (
    <>
      <PageHeader
        title="局域网与客户端"
        description="对外 DNS 服务、访问控制、速率限制与客户端识别"
      />
      <div className="space-y-3.5">
        <div className="grid gap-3.5 xl:grid-cols-2">
          <LanServiceCard />
          <AccessControlCard />
        </div>
        <div className="grid gap-3.5 xl:grid-cols-[1.2fr_1fr]">
          <RateLimitCard />
          <ClientsCard />
        </div>
      </div>
    </>
  );
}
