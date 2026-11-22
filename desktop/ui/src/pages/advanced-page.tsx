import { Dns64Card } from "../components/advanced/dns64-card";
import { EcsCard } from "../components/advanced/ecs-card";
import { HostsCard } from "../components/advanced/hosts-card";
import { PrivacyCard } from "../components/advanced/privacy-card";
import { RebindCard } from "../components/advanced/rebind-card";
import { PageHeader } from "../components/layout/page-header";

export function AdvancedPage() {
  return (
    <>
      <PageHeader
        title="DNS 高级与隐私"
        description="协议加固、重绑定防御、Hosts、ECS 与 DNS64"
      />
      <div className="space-y-3.5">
        <PrivacyCard />
        <div className="card-grid-2">
          <RebindCard />
          <HostsCard />
        </div>
        <div className="card-grid-2">
          <EcsCard />
          <Dns64Card />
        </div>
      </div>
    </>
  );
}
