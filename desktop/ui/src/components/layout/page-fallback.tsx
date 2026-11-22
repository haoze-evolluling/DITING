import { Skeleton } from "../ui/skeleton";

export function PageFallback() {
  return (
    <div className="space-y-3.5" role="status" aria-label="正在加载页面">
      <div className="space-y-2">
        <Skeleton className="h-7 w-32" />
        <Skeleton className="h-4 w-56" />
      </div>
      <div className="grid gap-3.5 xl:grid-cols-[1.5fr_1fr]">
        <Skeleton className="h-[248px] w-full rounded-2xl" />
        <Skeleton className="h-[248px] w-full rounded-2xl" />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <Skeleton key={index} className="h-[104px] w-full rounded-2xl" />
        ))}
      </div>
    </div>
  );
}
