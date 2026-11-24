import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { ChevronDown, Download, FileJson, FileSpreadsheet } from "lucide-react";

import { Button } from "../ui/button";

const menuClass =
  "motion-popover z-[70] min-w-[176px] rounded-xl border border-border bg-surface p-1 shadow-[var(--shadow-pop)]";
const itemClass =
  "flex cursor-pointer select-none items-center gap-2 rounded-lg px-2.5 py-1.5 text-[12.5px] text-text outline-none data-[highlighted]:bg-surface-3";

export function ExportMenu({
  onExport,
  loading,
}: {
  onExport: (format: "csv" | "json") => void;
  loading: boolean;
}) {
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        <Button
          size="sm"
          variant="ghost"
          loading={loading}
          aria-label="导出查询日志"
        >
          <Download className="h-3.5 w-3.5" />
          导出
          <ChevronDown className="h-3 w-3 text-text-3" />
        </Button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content align="end" sideOffset={6} className={menuClass}>
          <DropdownMenu.Item
            className={itemClass}
            onSelect={() => onExport("csv")}
          >
            <FileSpreadsheet className="h-3.5 w-3.5 text-text-3" />
            <span className="flex-1">导出 CSV</span>
          </DropdownMenu.Item>
          <DropdownMenu.Item
            className={itemClass}
            onSelect={() => onExport("json")}
          >
            <FileJson className="h-3.5 w-3.5 text-text-3" />
            <span className="flex-1">导出 JSON</span>
          </DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
