import { useAuthStore } from "../stores/auth";

export interface DownloadResult {
  filename: string;
  exported: number;
  truncated: boolean;
}

/** 携带会话令牌下载文件，并读取服务端返回的导出元数据。 */
export async function downloadFile(
  path: string,
  fallbackFilename: string,
): Promise<DownloadResult> {
  const token = useAuthStore.getState().token;
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `下载失败（HTTP ${response.status}）`);
  }
  const disposition = response.headers.get("content-disposition") ?? "";
  const filename =
    /filename="?([^";]+)"?/i.exec(disposition)?.[1] ?? fallbackFilename;
  const exported = Number(response.headers.get("x-diting-export-count") ?? 0);
  const truncated =
    response.headers.get("x-diting-export-truncated") === "true";
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
  return { filename, exported, truncated };
}
