import { PageHeader } from "../components/layout/page-header";
import { SafeBrowsingCard } from "../components/safety/safebrowsing-card";
import { SafeSearchCard } from "../components/safety/safesearch-card";

export function SafetyPage() {
  return (
    <>
      <PageHeader
        title="安全搜索与浏览"
        description="强制安全搜索结果、威胁情报拦截与家长控制"
      />
      <div className="card-grid-2">
        <SafeSearchCard />
        <SafeBrowsingCard />
      </div>
    </>
  );
}
