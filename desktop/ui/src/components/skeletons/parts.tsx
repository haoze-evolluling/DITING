import type { ReactNode } from "react";

import { cn } from "../../lib/cn";
import { Card } from "../ui/card";
import { Skeleton } from "../ui/skeleton";

/*
 * 骨架原语：尺寸与真实组件对齐，保证加载态和内容态占用同一块布局。
 * 所有原语只组合 Skeleton，不引入自己的动画，动效档位由 .motion-skeleton 统一控制。
 */

/** 页面标题占位，对齐 PageHeader 的 21px 标题、描述与右侧操作区。 */
export function PageHeaderSkeleton({ actions = 1 }: { actions?: number }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
      <div className="min-w-0">
        <Skeleton className="h-7 w-36 rounded-md" />
        <Skeleton className="mt-1.5 h-3.5 w-64 max-w-[72vw] rounded-md" />
      </div>
      {actions > 0 ? (
        <div className="ml-auto flex flex-wrap items-center gap-2">
          {Array.from({ length: actions }).map((_, index) => (
            <Skeleton key={index} className="h-8 w-[76px] rounded-lg" />
          ))}
        </div>
      ) : null}
    </div>
  );
}

/** 卡片头占位，对齐 CardHeader 的 px-5 / pt-4 与标题、描述行高。 */
export function CardHeaderSkeleton({
  titleWidth = "w-24",
  description = true,
  descriptionWidth = "w-48",
  action = false,
}: {
  titleWidth?: string;
  description?: boolean;
  descriptionWidth?: string;
  action?: boolean;
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-5 pt-4">
      <div className="min-w-0 flex-1">
        <Skeleton className={cn("h-4 rounded-md", titleWidth)} />
        {description ? (
          <Skeleton className={cn("mt-1.5 h-3 max-w-full rounded-md", descriptionWidth)} />
        ) : null}
      </div>
      {action ? <Skeleton className="h-7 w-16 shrink-0 rounded-lg" /> : null}
    </div>
  );
}

/** 卡片外壳，保持与真实 Card 相同的圆角、边框和阴影。 */
export function CardSkeleton({
  className,
  children,
}: {
  className?: string;
  children?: ReactNode;
}) {
  return <Card className={cn("flex flex-col", className)}>{children}</Card>;
}

/** 卡片底部操作条占位。 */
export function CardFooterSkeleton({ action = true }: { action?: boolean }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-t border-border px-5 py-3">
      <Skeleton className="h-2.5 w-32 rounded-md" />
      {action ? <Skeleton className="h-8 w-16 rounded-lg" /> : null}
    </div>
  );
}

/** 列表行占位：状态点 + 两行主副文案 + 右侧数值，对齐上游/网卡/排行榜行。 */
export function ListRowsSkeleton({
  rows = 3,
  meta = true,
  className,
}: {
  rows?: number;
  meta?: boolean;
  className?: string;
}) {
  return (
    <div className={cn("divide-y divide-border/60", className)}>
      {Array.from({ length: rows }).map((_, index) => (
        <div key={index} className="flex items-center gap-3 py-2.5">
          <Skeleton className="h-1.5 w-1.5 shrink-0 rounded-full" />
          <div className="min-w-0 flex-1 space-y-1.5">
            <Skeleton className="h-3.5 w-[42%] rounded-md" />
            {meta ? <Skeleton className="h-2.5 w-[64%] rounded-md" /> : null}
          </div>
          <Skeleton className="h-3.5 w-10 shrink-0 rounded-md" />
        </div>
      ))}
    </div>
  );
}

/** 开关行占位：左侧标题与说明，右侧开关轨道，对齐 SwitchRow。 */
export function SwitchRowsSkeleton({
  rows = 3,
  className,
}: {
  rows?: number;
  className?: string;
}) {
  return (
    <div className={className}>
      {Array.from({ length: rows }).map((_, index) => (
        <div
          key={index}
          className="flex items-center justify-between gap-4 border-b border-border/60 py-2.5 last:border-b-0"
        >
          <div className="min-w-0 space-y-1.5">
            <Skeleton className="h-3 w-32 max-w-[46vw] rounded-md" />
            <Skeleton className="h-2.5 w-48 max-w-[60vw] rounded-md" />
          </div>
          <Skeleton className="h-5 w-9 shrink-0 rounded-full" />
        </div>
      ))}
    </div>
  );
}

/** 信息行占位：左侧标签 + 右侧值，对齐设置页 InfoRow。 */
export function InfoRowsSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div>
      {Array.from({ length: rows }).map((_, index) => (
        <div
          key={index}
          className="flex items-center justify-between gap-4 border-b border-border/60 py-2.5 last:border-b-0"
        >
          <Skeleton className="h-2.5 w-16 shrink-0 rounded-md" />
          <Skeleton className="h-3 w-28 max-w-[50%] rounded-md" />
        </div>
      ))}
    </div>
  );
}

/** 表单字段占位：标签 + 输入框 + 提示，对齐 Field。 */
export function FieldGridSkeleton({
  fields = 2,
  columns = 2,
}: {
  fields?: number;
  columns?: 1 | 2;
}) {
  return (
    <div className={cn("grid gap-3", columns === 2 && "sm:grid-cols-2")}>
      {Array.from({ length: fields }).map((_, index) => (
        <div key={index} className="space-y-1.5">
          <Skeleton className="h-3 w-20 rounded-md" />
          <Skeleton className="h-9 w-full rounded-lg" />
          <Skeleton className="h-2.5 w-28 rounded-md" />
        </div>
      ))}
    </div>
  );
}

/** 多行文本框占位。 */
export function TextareaSkeleton({ className }: { className?: string }) {
  return <Skeleton className={cn("h-24 w-full rounded-lg", className)} />;
}

/** 图表绘图区占位，高度与 TrafficChart 的 228px 绘图区一致。 */
export function ChartSkeleton({ className }: { className?: string }) {
  return <Skeleton className={cn("h-[228px] w-full rounded-lg", className)} />;
}

/** 表头 + 数据行占位，用于查询日志、缓存条目等表格型卡片。 */
export function TableRowsSkeleton({
  rows = 7,
  columns = 5,
  className,
}: {
  rows?: number;
  columns?: number;
  className?: string;
}) {
  return (
    <div className={cn("min-w-0", className)}>
      <div className="flex items-center gap-4 border-b border-border/60 px-3 py-2">
        {Array.from({ length: columns }).map((_, index) => (
          <Skeleton
            key={index}
            className={cn("h-2.5 rounded", index === 0 ? "w-14 shrink-0" : "min-w-0 flex-1")}
          />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, row) => (
        <div
          key={row}
          className="flex items-center gap-4 border-b border-border/50 px-3 py-2.5 last:border-b-0"
        >
          {Array.from({ length: columns }).map((_, column) => (
            <Skeleton
              key={column}
              className={cn(
                "h-3 rounded",
                column === 0 ? "w-16 shrink-0" : "min-w-0 flex-1",
                column === columns - 1 && "max-w-16",
              )}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

/** 指标卡占位，对齐 StatTile 的标签、数值与提示三行结构。 */
export function StatTileSkeleton({ className }: { className?: string }) {
  return (
    <Card className={cn("min-w-0 px-4 py-3.5", className)}>
      <div className="flex min-w-0 items-center justify-between gap-3">
        <Skeleton className="h-3 w-20 rounded-md" />
        <Skeleton className="h-7 w-7 shrink-0 rounded-lg" />
      </div>
      <Skeleton className="mt-3 h-7 w-24 rounded-md" />
      <Skeleton className="mt-2 h-3 w-28 max-w-full rounded-md" />
    </Card>
  );
}

/** 四列指标区，与 card-grid-4 共用同一组轨道。 */
export function StatTilesSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="card-grid-4">
      {Array.from({ length: count }).map((_, index) => (
        <StatTileSkeleton key={index} />
      ))}
    </div>
  );
}

/** 概览页 HeroStatus 占位，含顶部操作、运行状态、QPS 走势与底部四项指标。 */
export function HeroStatusSkeleton({ className }: { className?: string }) {
  return (
    <Card
      className={cn(
        "card-sheen relative flex min-h-[248px] flex-col overflow-hidden",
        className,
      )}
    >
      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-5 pt-4">
        <div className="flex flex-wrap items-center gap-2">
          <Skeleton className="h-3 w-14 rounded-md" />
          <Skeleton className="h-5 w-20 rounded-md" />
        </div>
        <div className="ml-auto flex flex-wrap items-center gap-2">
          <Skeleton className="h-8 w-20 rounded-lg" />
          <Skeleton className="h-8 w-24 rounded-lg" />
        </div>
      </div>

      <div className="flex flex-1 flex-col justify-between gap-4 px-5 pb-4 pt-3">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2.5">
              <Skeleton className="h-2.5 w-2.5 rounded-full" />
              <Skeleton className="h-8 w-32 rounded-md" />
            </div>
            <Skeleton className="mt-2 h-3 w-56 max-w-[60vw] rounded-md" />
            <div className="mt-3 flex flex-wrap gap-1.5">
              <Skeleton className="h-4 w-24 rounded-md" />
              <Skeleton className="h-4 w-20 rounded-md" />
            </div>
          </div>
          <div className="ml-auto shrink-0 space-y-1.5">
            <Skeleton className="ml-auto h-7 w-16 rounded-md" />
            <Skeleton className="ml-auto h-2.5 w-12 rounded-md" />
          </div>
        </div>
        <Skeleton className="h-9 w-full rounded-md" />
      </div>

      <div className="grid grid-cols-2 border-t border-border bg-surface-2/65 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="min-w-0 space-y-1.5 px-4 py-2.5">
            <Skeleton className="h-2.5 w-12 rounded-md" />
            <Skeleton className="h-3.5 w-16 rounded-md" />
          </div>
        ))}
      </div>
    </Card>
  );
}

/** 趋势图卡占位：卡片头 + 图例 + 绘图区，对齐 TrafficChart 的结构。 */
export function TrafficCardSkeleton({
  className,
  titleWidth = "w-28",
}: {
  className?: string;
  titleWidth?: string;
}) {
  return (
    <CardSkeleton className={cn("overflow-hidden", className)}>
      <CardHeaderSkeleton titleWidth={titleWidth} action />
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 pt-3">
        <Skeleton className="h-3 w-14 rounded-md" />
        <Skeleton className="h-3 w-14 rounded-md" />
        <Skeleton className="h-3 w-16 rounded-md" />
        <Skeleton className="ml-auto h-3 w-20 rounded-md" />
      </div>
      <div className="px-5 pb-4 pt-2">
        <ChartSkeleton />
      </div>
    </CardSkeleton>
  );
}
