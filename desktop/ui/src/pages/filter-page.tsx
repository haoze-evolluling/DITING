import { BlockedServicesCard } from "../components/filters/blocked-services-card";
import { CustomRulesCard } from "../components/filters/custom-rules-card";
import { FilterListsCard } from "../components/filters/filter-lists-card";
import { FilterOverviewCard } from "../components/filters/filter-overview-card";
import { ScheduleCard } from "../components/filters/schedule-card";
import { PageHeader } from "../components/layout/page-header";

export function FilterPage() {
  return (
    <>
      <PageHeader
        title="规则与拦截"
        description="订阅源、自定义规则、内置服务与时间计划"
      />
      <div className="space-y-3.5">
        <div className="grid gap-3.5 xl:grid-cols-2">
          <FilterOverviewCard />
          <ScheduleCard />
        </div>
        <div className="grid gap-3.5 xl:grid-cols-[1.2fr_1fr]">
          <FilterListsCard />
          <CustomRulesCard />
        </div>
        <BlockedServicesCard />
      </div>
    </>
  );
}
