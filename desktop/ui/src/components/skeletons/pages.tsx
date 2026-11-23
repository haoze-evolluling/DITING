import { Skeleton } from "../ui/skeleton";
import {
  CardFooterSkeleton,
  CardHeaderSkeleton,
  CardSkeleton,
  ChartSkeleton,
  FieldGridSkeleton,
  HeroStatusSkeleton,
  InfoRowsSkeleton,
  ListRowsSkeleton,
  PageHeaderSkeleton,
  StatTilesSkeleton,
  SwitchRowsSkeleton,
  TableRowsSkeleton,
  TextareaSkeleton,
  TrafficCardSkeleton,
} from "./parts";

/*
 * 路由骨架模板：每个页面复用真实页面的网格类（card-grid-2 / 3-1 / 4）
 * 与卡片顺序，使骨架卡片的位置、宽度、分界线与内容完全一致。
 */

/** 普通列表卡：卡片头 + N 行列表。 */
function ListCardSkeleton({
  rows = 3,
  titleWidth = "w-20",
  action = true,
  meta = true,
  className,
}: {
  rows?: number;
  titleWidth?: string;
  action?: boolean;
  meta?: boolean;
  className?: string;
}) {
  return (
    <CardSkeleton className={className}>
      <CardHeaderSkeleton titleWidth={titleWidth} action={action} />
      <div className="flex flex-1 flex-col px-5 pb-4 pt-3">
        <ListRowsSkeleton rows={rows} meta={meta} />
      </div>
    </CardSkeleton>
  );
}

/** 开关表单卡：卡片头 + 开关行 +（可选）字段网格。 */
function FormCardSkeleton({
  rows = 3,
  fields = 0,
  columns = 2,
  titleWidth = "w-24",
  action = false,
  footer = false,
  className,
}: {
  rows?: number;
  fields?: number;
  columns?: 1 | 2;
  titleWidth?: string;
  action?: boolean;
  footer?: boolean;
  className?: string;
}) {
  return (
    <CardSkeleton className={className}>
      <CardHeaderSkeleton titleWidth={titleWidth} action={action} />
      <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
        <SwitchRowsSkeleton rows={rows} />
        {fields > 0 ? <FieldGridSkeleton fields={fields} columns={columns} /> : null}
      </div>
      {footer ? <CardFooterSkeleton /> : null}
    </CardSkeleton>
  );
}

/** 表格卡：统计条 + 表头数据行 + 底部操作条。 */
function TableCardSkeleton({
  rows = 8,
  columns = 6,
  footer = true,
}: {
  rows?: number;
  columns?: number;
  footer?: boolean;
}) {
  return (
    <CardSkeleton className="overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-2.5">
        <div className="flex items-center gap-2">
          <Skeleton className="h-1.5 w-1.5 rounded-full" />
          <Skeleton className="h-3 w-24 rounded-md" />
          <Skeleton className="h-3 w-14 rounded-md" />
        </div>
        <Skeleton className="h-3 w-28 rounded-md" />
      </div>
      <TableRowsSkeleton rows={rows} columns={columns} />
      {footer ? <CardFooterSkeleton /> : null}
    </CardSkeleton>
  );
}

export function DashboardSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={1} />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <HeroStatusSkeleton />
          <TrafficCardSkeleton className="min-h-[248px]" />
        </div>
        <StatTilesSkeleton />
        <div className="card-grid-2">
          <ListCardSkeleton rows={3} titleWidth="w-24" />
          <ListCardSkeleton rows={2} titleWidth="w-28" />
        </div>
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-24" action />
          <div className="flex-1 px-2 pb-3 pt-1">
            <TableRowsSkeleton rows={5} columns={5} />
          </div>
        </CardSkeleton>
      </div>
    </>
  );
}

export function LogsSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={2} />
      <div className="space-y-3.5">
        <TrafficCardSkeleton titleWidth="w-24" />
        <div className="card-grid-2">
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" />
            <div className="grid flex-1 grid-cols-2 content-center gap-x-4 gap-y-6 px-5 pb-4 pt-3">
              {Array.from({ length: 4 }).map((_, index) => (
                <div key={index} className="space-y-1.5">
                  <Skeleton className="h-2.5 w-14 rounded-md" />
                  <Skeleton className="h-6 w-20 rounded-md" />
                </div>
              ))}
            </div>
          </CardSkeleton>
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-16" action />
            <div className="flex flex-1 flex-col gap-1.5 px-5 pb-4 pt-1">
              {Array.from({ length: 7 }).map((_, index) => (
                <Skeleton key={index} className="h-7 w-full rounded-md" />
              ))}
            </div>
          </CardSkeleton>
        </div>

        <div className="min-w-0 space-y-3.5">
          <CardSkeleton>
            <div className="flex flex-wrap items-center gap-2 px-3.5 pt-3">
              <Skeleton className="h-9 min-w-[170px] flex-1 rounded-lg" />
              <Skeleton className="h-9 min-w-[160px] flex-1 rounded-lg" />
              <Skeleton className="h-9 w-[136px] shrink-0 rounded-lg" />
              <Skeleton className="h-9 w-[118px] shrink-0 rounded-lg" />
              <Skeleton className="h-8 w-14 shrink-0 rounded-lg" />
              <Skeleton className="h-8 w-14 shrink-0 rounded-lg" />
            </div>
            <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 border-t border-border/70 px-3.5 py-2">
              <Skeleton className="h-2.5 w-64 max-w-[50%] rounded-md" />
              <div className="flex items-center gap-2">
                <Skeleton className="h-5 w-9 rounded-full" />
                <Skeleton className="h-8 w-16 rounded-lg" />
              </div>
            </div>
          </CardSkeleton>
          <TableCardSkeleton rows={9} columns={6} />
        </div>
      </div>
    </>
  );
}

export function CacheSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={2} />
      <div className="space-y-3.5">
        <StatTilesSkeleton />
        <div className="card-grid-3-1">
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-24" action />
            <div className="px-5 pt-2">
              <div className="flex flex-col gap-2 sm:flex-row">
                <Skeleton className="h-9 flex-1 rounded-lg" />
                <Skeleton className="h-9 shrink-0 rounded-lg sm:w-[110px]" />
                <Skeleton className="h-9 w-16 shrink-0 rounded-lg" />
              </div>
            </div>
            <div className="flex-1 px-5 pb-4 pt-3">
              <TableRowsSkeleton rows={6} columns={5} />
            </div>
          </CardSkeleton>
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" action />
            <div className="flex flex-1 flex-col px-5 pb-4 pt-2">
              <ListRowsSkeleton rows={3} />
            </div>
          </CardSkeleton>
        </div>
        <div className="card-grid-2">
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <SwitchRowsSkeleton rows={2} />
              <FieldGridSkeleton fields={2} />
              <TextareaSkeleton className="h-[72px]" />
            </div>
            <CardFooterSkeleton />
          </CardSkeleton>
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-24" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <Skeleton className="h-[52px] w-full rounded-xl" />
              <div className="grid grid-cols-3 gap-2">
                {Array.from({ length: 3 }).map((_, index) => (
                  <Skeleton key={index} className="h-14 w-full rounded-xl" />
                ))}
              </div>
              <div className="mt-auto flex items-center gap-2 pt-1">
                <Skeleton className="h-8 w-20 rounded-lg" />
                <Skeleton className="h-8 w-24 rounded-lg" />
              </div>
            </div>
          </CardSkeleton>
        </div>
      </div>
    </>
  );
}

export function FilterSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <SwitchRowsSkeleton rows={1} />
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {Array.from({ length: 4 }).map((_, index) => (
                  <Skeleton key={index} className="h-[62px] w-full rounded-xl" />
                ))}
              </div>
              <Skeleton className="h-[68px] w-full rounded-xl" />
            </div>
          </CardSkeleton>
          <FormCardSkeleton rows={2} fields={2} titleWidth="w-24" action />
        </div>
        <div className="card-grid-2">
          <ListCardSkeleton rows={5} titleWidth="w-20" action />
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-24" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <TextareaSkeleton className="h-[180px]" />
              <div className="flex items-center gap-2">
                <Skeleton className="h-8 w-20 rounded-lg" />
                <Skeleton className="h-8 w-16 rounded-lg" />
              </div>
            </div>
          </CardSkeleton>
        </div>
        <ListCardSkeleton rows={3} titleWidth="w-28" action />
      </div>
    </>
  );
}

export function SafetySkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="card-grid-2">
        <FormCardSkeleton rows={2} fields={2} titleWidth="w-24" action />
        <FormCardSkeleton rows={2} fields={1} columns={1} titleWidth="w-28" action />
      </div>
    </>
  );
}

export function AdvancedSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="space-y-3.5">
        <FormCardSkeleton rows={5} titleWidth="w-28" action />
        <div className="card-grid-2">
          <FormCardSkeleton rows={1} fields={1} columns={1} titleWidth="w-24" action />
          <FormCardSkeleton rows={1} fields={1} columns={1} titleWidth="w-20" action />
        </div>
        <div className="card-grid-2">
          <FormCardSkeleton rows={2} fields={2} titleWidth="w-16" action />
          <FormCardSkeleton rows={1} fields={1} columns={1} titleWidth="w-20" action />
        </div>
      </div>
    </>
  );
}

export function UpstreamSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={2} />
      <div className="space-y-3.5">
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-20" />
          <div className="flex flex-wrap items-center justify-between gap-3 px-5 pb-4 pt-3">
            <Skeleton className="h-8 w-64 max-w-full rounded-lg" />
            <Skeleton className="h-3 w-24 rounded-md" />
          </div>
        </CardSkeleton>
        <div className="card-grid-2">
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-24" action />
            <div className="flex flex-1 flex-col px-5 pb-3 pt-3">
              <ListRowsSkeleton rows={3} />
            </div>
            <CardFooterSkeleton />
          </CardSkeleton>
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-28" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <SwitchRowsSkeleton rows={1} />
              <ListRowsSkeleton rows={2} />
            </div>
            <CardFooterSkeleton action={false} />
          </CardSkeleton>
        </div>
      </div>
    </>
  );
}

export function RewriteSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={1} />
      <div className="grid gap-3.5">
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-24" action />
          <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
            <SwitchRowsSkeleton rows={1} />
            <FieldGridSkeleton fields={2} />
            <TextareaSkeleton className="h-[180px]" />
          </div>
          <CardFooterSkeleton />
        </CardSkeleton>
      </div>
    </>
  );
}

export function LanSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <FormCardSkeleton rows={2} fields={2} titleWidth="w-24" action />
          <ListCardSkeleton rows={4} titleWidth="w-24" action />
        </div>
        <div className="card-grid-2">
          <FormCardSkeleton rows={2} fields={2} titleWidth="w-20" action />
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" action />
            <div className="flex-1 px-5 pb-4 pt-2">
              <TableRowsSkeleton rows={5} columns={4} />
            </div>
          </CardSkeleton>
        </div>
        <ListCardSkeleton rows={4} titleWidth="w-24" action />
      </div>
    </>
  );
}

export function EncryptedSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <FormCardSkeleton rows={3} fields={2} titleWidth="w-24" action />
          <CardSkeleton>
            <CardHeaderSkeleton titleWidth="w-20" action />
            <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
              <InfoRowsSkeleton rows={3} />
              <div className="flex flex-wrap gap-2">
                <Skeleton className="h-8 w-24 rounded-lg" />
                <Skeleton className="h-8 w-28 rounded-lg" />
              </div>
            </div>
          </CardSkeleton>
        </div>
        <FormCardSkeleton rows={1} fields={1} columns={1} titleWidth="w-28" action />
      </div>
    </>
  );
}

export function SettingsSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={0} />
      <div className="card-grid-2">
        <FormCardSkeleton rows={2} fields={2} titleWidth="w-20" footer />
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-24" />
          <div className="flex flex-1 flex-col px-5 pb-4 pt-3">
            <InfoRowsSkeleton rows={3} />
          </div>
          <CardFooterSkeleton />
        </CardSkeleton>
        <FormCardSkeleton rows={3} fields={2} titleWidth="w-20" footer />
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-20" action />
          <div className="flex flex-1 flex-col px-5 pb-4 pt-3">
            <InfoRowsSkeleton rows={6} />
          </div>
        </CardSkeleton>
        <FormCardSkeleton rows={3} fields={2} titleWidth="w-20" footer />
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-20" action />
          <div className="flex flex-1 flex-col gap-1 px-5 pb-4 pt-3">
            {Array.from({ length: 8 }).map((_, index) => (
              <Skeleton key={index} className="h-[46px] w-full rounded-xl" />
            ))}
          </div>
        </CardSkeleton>
        <FormCardSkeleton rows={0} fields={2} titleWidth="w-24" footer />
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-16" action />
          <div className="flex flex-1 flex-col gap-3 px-5 pb-4 pt-3">
            <div className="flex items-center gap-3">
              <Skeleton className="h-11 w-11 rounded-xl" />
              <div className="space-y-1.5">
                <Skeleton className="h-4 w-24 rounded-md" />
                <Skeleton className="h-2.5 w-40 rounded-md" />
              </div>
            </div>
            <Skeleton className="h-3 w-full rounded-md" />
            <Skeleton className="h-3 w-4/5 rounded-md" />
            <InfoRowsSkeleton rows={3} />
          </div>
        </CardSkeleton>
      </div>
    </>
  );
}

export function GenericPageSkeleton() {
  return (
    <>
      <PageHeaderSkeleton actions={1} />
      <div className="space-y-3.5">
        <div className="card-grid-2">
          <CardSkeleton className="min-h-[248px]">
            <CardHeaderSkeleton titleWidth="w-24" action />
            <div className="flex-1 px-5 pb-4 pt-3">
              <ListRowsSkeleton rows={3} />
            </div>
          </CardSkeleton>
          <CardSkeleton className="min-h-[248px]">
            <CardHeaderSkeleton titleWidth="w-28" action />
            <div className="flex-1 px-5 pb-4 pt-3">
              <ChartSkeleton className="h-[150px]" />
            </div>
          </CardSkeleton>
        </div>
        <StatTilesSkeleton />
        <CardSkeleton>
          <CardHeaderSkeleton titleWidth="w-24" action />
          <div className="flex-1 px-2 pb-3 pt-1">
            <TableRowsSkeleton rows={5} columns={5} />
          </div>
        </CardSkeleton>
      </div>
    </>
  );
}
