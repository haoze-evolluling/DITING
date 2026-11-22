import { useState } from "react";
import { FileCode2, Waypoints } from "lucide-react";

import { PageHeader } from "../components/layout/page-header";
import { RewriteRulesCard } from "../components/rewrite/rewrite-rules-card";
import { ZoneCard } from "../components/rewrite/zone-card";
import { Segmented } from "../components/ui/segmented";

type Tab = "rewrite" | "zone";

export function RewritePage() {
  const [tab, setTab] = useState<Tab>("rewrite");

  return (
    <>
      <PageHeader
        title="重写与区文件"
        description="自定义域名应答，或为内网域名提供本地权威解析"
        actions={
          <Segmented
            value={tab}
            options={[
              { value: "rewrite", label: "域名重写", icon: Waypoints },
              { value: "zone", label: "区文件", icon: FileCode2 },
            ]}
            onChange={setTab}
          />
        }
      />
      <div className="grid gap-3.5">{tab === "rewrite" ? <RewriteRulesCard /> : <ZoneCard />}</div>
    </>
  );
}
