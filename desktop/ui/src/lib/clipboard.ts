import { toast } from "sonner";

export function copyText(value: string, label: string) {
  navigator.clipboard
    .writeText(value)
    .then(() => toast.success(`${label}已复制`))
    .catch(() => toast.error("无法访问剪贴板"));
}
