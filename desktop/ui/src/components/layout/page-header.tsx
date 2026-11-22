import type { ReactNode } from "react";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
      <div className="min-w-0">
        <h1 className="text-[21px] font-semibold tracking-[-0.03em] text-text">{title}</h1>
        {description ? (
          <p className="mt-1 text-[12.5px] text-text-3">{description}</p>
        ) : null}
      </div>
      {actions ? (
        <div className="ml-auto flex flex-wrap items-center gap-2">{actions}</div>
      ) : null}
    </div>
  );
}
