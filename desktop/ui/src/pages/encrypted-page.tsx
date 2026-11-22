import { EncryptedAclCard } from "../components/encrypted/acl-card";
import { CertCard } from "../components/encrypted/cert-card";
import { EncryptedServiceCard } from "../components/encrypted/encrypted-service-card";
import { PageHeader } from "../components/layout/page-header";

export function EncryptedPage() {
  return (
    <>
      <PageHeader
        title="加密 DNS"
        description="DoT / DoH 监听、服务证书与反向代理来源"
      />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <EncryptedServiceCard />
          <CertCard />
        </div>
        <EncryptedAclCard />
      </div>
    </>
  );
}
