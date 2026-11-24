import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Image as ImageIcon, Link2, RotateCcw, Save, Upload } from "lucide-react";
import { toast } from "sonner";

import { useLoginBackground } from "../../hooks/use-api";
import { api, describeError } from "../../lib/api";
import type { LoginBackgroundType } from "../../lib/types";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";
import { LoadingState } from "../ui/loading";
import { Segmented } from "../ui/segmented";

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
// 服务端请求体上限 4 MiB，base64 会放大约 1/3，这里给 JSON 字段留出余量。
const MAX_ENCODED_LENGTH = 3_600_000;
const MAX_IMAGE_EDGE = 2560;
const MAX_URL_LEN = 2048;
const ACCEPTED_TYPES = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"];
const CUSTOM_IMAGE_URL = "/api/v1/auth/background/image";

const sourceOptions: { value: LoginBackgroundType; label: string }[] = [
  { value: "none", label: "系统默认" },
  { value: "custom", label: "本地图片" },
  { value: "url", label: "网络链接" },
];

function cssImageUrl(url: string): string {
  const safe = url.replace(/["\\\n\r]/g, "").trim();
  return `url("${safe}")`;
}

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") {
        resolve(reader.result);
      } else {
        reject(new Error("读取图片失败"));
      }
    };
    reader.onerror = () => reject(new Error("读取图片失败"));
    reader.readAsDataURL(file);
  });
}

/** 将过大的位图降采样并重新编码，避免 Base64 后超过管理 API 的请求体上限。 */
async function prepareImage(file: File): Promise<string> {
  const original = await readAsDataUrl(file);
  if (original.length <= MAX_ENCODED_LENGTH) return original;
  if (file.type === "image/svg+xml") {
    throw new Error("SVG 图片体积过大，请精简后再上传");
  }

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    throw new Error("图片过大且无法在浏览器内压缩，请改用更小的图片");
  }

  try {
    const scale = Math.min(1, MAX_IMAGE_EDGE / Math.max(bitmap.width, bitmap.height));
    let width = Math.max(1, Math.round(bitmap.width * scale));
    let height = Math.max(1, Math.round(bitmap.height * scale));

    for (let attempt = 0; attempt < 4; attempt += 1) {
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext("2d");
      if (!context) break;
      context.drawImage(bitmap, 0, 0, width, height);
      for (const quality of [0.9, 0.8, 0.7, 0.6]) {
        const encoded = canvas.toDataURL("image/webp", quality);
        if (encoded.length <= MAX_ENCODED_LENGTH) return encoded;
      }
      width = Math.max(1, Math.round(width * 0.75));
      height = Math.max(1, Math.round(height * 0.75));
    }
  } finally {
    bitmap.close();
  }

  throw new Error("图片压缩后仍超过上传上限，请改用更小的图片");
}

function RangeField({
  label,
  value,
  min,
  max,
  suffix,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  suffix: string;
  onChange: (value: number) => void;
}) {
  return (
    <label className="block">
      <span className="flex items-center justify-between text-[12px] text-text-2">
        {label}
        <span className="num text-[11px] text-text-3">
          {value}
          {suffix}
        </span>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
        className="mt-1.5 w-full cursor-pointer accent-accent"
      />
    </label>
  );
}

export function LoginBackgroundCard() {
  const background = useLoginBackground();
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);

  const [mode, setMode] = useState<LoginBackgroundType>("none");
  const [url, setUrl] = useState("");
  const [opacity, setOpacity] = useState(40);
  const [blur, setBlur] = useState(0);
  const [upload, setUpload] = useState<string | null>(null);
  const [uploadName, setUploadName] = useState("");
  const [processing, setProcessing] = useState(false);

  const data = background.data;

  useEffect(() => {
    if (!data) return;
    setMode(data.type === "url" ? "url" : data.type === "custom" ? "custom" : "none");
    setUrl(data.type === "url" ? data.url : "");
    setOpacity(data.opacity);
    setBlur(data.blur);
    setUpload(null);
    setUploadName("");
  }, [data]);

  const hasStoredCustom = data?.type === "custom";
  const trimmedUrl = url.trim();
  const previewUrl = useMemo(() => {
    if (mode === "custom") return upload ?? (hasStoredCustom ? data?.url ?? "" : "");
    if (mode === "url") return /^https?:\/\//i.test(trimmedUrl) ? trimmedUrl : "";
    return "";
  }, [mode, upload, hasStoredCustom, data?.url, trimmedUrl]);

  const dirty = useMemo(() => {
    if (!data) return false;
    if (mode !== data.type) return true;
    if (opacity !== data.opacity || blur !== data.blur) return true;
    if (mode === "url" && trimmedUrl !== data.url) return true;
    if (mode === "custom" && upload) return true;
    return false;
  }, [data, mode, opacity, blur, trimmedUrl, upload]);

  const valid =
    mode === "none" ||
    (mode === "custom" && (Boolean(upload) || hasStoredCustom)) ||
    (mode === "url" && /^https?:\/\//i.test(trimmedUrl) && trimmedUrl.length <= MAX_URL_LEN);

  const applyResult = (result: Awaited<ReturnType<typeof api.setLoginBackground>>) => {
    queryClient.setQueryData(["login-background"], result);
    void queryClient.invalidateQueries({ queryKey: ["login-background"] });
  };

  const save = useMutation({
    mutationFn: () =>
      mode === "none"
        ? api.resetLoginBackground()
        : api.setLoginBackground({
            type: mode,
            url: mode === "custom" ? (upload ?? CUSTOM_IMAGE_URL) : trimmedUrl,
            opacity,
            blur,
          }),
    onSuccess: (result) => {
      applyResult(result);
      toast.success(result.type === "none" ? "已恢复系统默认背景" : "登录页背景已保存并应用");
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const reset = useMutation({
    mutationFn: api.resetLoginBackground,
    onSuccess: (result) => {
      applyResult(result);
      toast.success("已恢复系统默认背景");
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const pickFile = async (file: File | undefined) => {
    if (!file) return;
    if (!ACCEPTED_TYPES.includes(file.type)) {
      toast.error("仅支持 PNG、JPEG、WebP 与 SVG 图片");
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      toast.error("图片体积不能超过 10MB");
      return;
    }
    setProcessing(true);
    try {
      const result = await prepareImage(file);
      setUpload(result);
      setUploadName(file.name);
      setMode("custom");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "读取图片失败");
    } finally {
      setProcessing(false);
    }
  };

  const badgeTone = !data || data.type === "none" ? "neutral" : "accent";
  const badgeLabel = !data
    ? "读取中"
    : data.type === "url"
      ? "网络图片"
      : data.type === "custom"
        ? "本地图片"
        : "系统默认";

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="登录页背景"
        description="为管理端登录页设置本地图片或网络图片，保存后立即应用。"
        actions={
          <Badge tone={badgeTone} dot>
            {badgeLabel}
          </Badge>
        }
      />
      <CardContent className="flex flex-1 flex-col gap-3.5 pt-3">
        {background.isLoading ? (
          <LoadingState label="正在加载登录背景…" />
        ) : !data ? (
          <div className="flex items-center justify-between gap-3 rounded-xl border border-warn/30 bg-warn-soft px-3 py-2.5 text-[11.5px] text-warn">
            <span>无法读取登录背景配置。</span>
            <Button
              size="sm"
              variant="ghost"
              className="text-warn hover:bg-warn/10 hover:text-warn"
              loading={background.isFetching}
              onClick={() => void background.refetch()}
            >
              重试
            </Button>
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="flex items-center gap-2 text-[12px] text-text-2">
                <ImageIcon className="h-3.5 w-3.5 text-text-3" />
                背景来源
              </span>
              <Segmented
                value={mode}
                options={sourceOptions}
                onChange={(value) => setMode(value)}
              />
            </div>

            <div className="relative aspect-[16/7] overflow-hidden rounded-xl border border-border bg-[#08121f]">
              {previewUrl ? (
                <div
                  className="absolute inset-0 bg-cover bg-center"
                  style={{
                    backgroundImage: cssImageUrl(previewUrl),
                    opacity: Math.min(100, Math.max(0, opacity)) / 100,
                    filter: blur > 0 ? `blur(${blur}px)` : undefined,
                    transform: blur > 0 ? "scale(1.06)" : undefined,
                  }}
                />
              ) : (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 text-white/35">
                  <ImageIcon className="h-5 w-5" />
                  <span className="text-[11px]">未设置背景，登录页使用系统默认样式</span>
                </div>
              )}
              <div
                aria-hidden
                className="absolute inset-0 bg-gradient-to-t from-[#08121f] via-[#08121f]/70 to-[#08121f]/30"
              />
              <span className="absolute bottom-2 left-3 text-[10px] tracking-[0.18em] text-white/55">
                登录页预览
              </span>
            </div>

            {mode === "custom" ? (
              <div className="rounded-xl border border-border bg-surface-2 px-3 py-2.5">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[12px] text-text">本地图片</div>
                    <div className="mt-0.5 truncate text-[10.5px] text-text-3">
                      {uploadName ||
                        (hasStoredCustom
                          ? "已保存自定义背景，可选择新图片替换"
                          : "支持 PNG、JPEG、WebP、SVG，最大 10MB，大图会自动压缩")}
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5">
                    {upload ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          setUpload(null);
                          setUploadName("");
                        }}
                      >
                        取消选择
                      </Button>
                    ) : null}
                    <Button
                      size="sm"
                      variant="secondary"
                      loading={processing}
                      onClick={() => fileRef.current?.click()}
                    >
                      <Upload className="h-3.5 w-3.5" />
                      选择图片
                    </Button>
                  </div>
                </div>
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                  className="hidden"
                  onChange={(event) => {
                    pickFile(event.target.files?.[0]);
                    event.target.value = "";
                  }}
                />
              </div>
            ) : null}

            {mode === "url" ? (
              <Field
                label="图片链接"
                hint="支持 http/https 链接，最长 2048 字符；图片由浏览器直接加载。"
              >
                <Input
                  leading={<Link2 className="h-3.5 w-3.5" />}
                  value={url}
                  onChange={(event) => setUrl(event.target.value)}
                  placeholder="https://example.com/background.jpg"
                  spellCheck={false}
                />
              </Field>
            ) : null}

            {mode !== "none" ? (
              <div className="grid gap-3 border-t border-border/60 pt-3.5 sm:grid-cols-2">
                <RangeField
                  label="不透明度"
                  value={opacity}
                  min={0}
                  max={100}
                  suffix="%"
                  onChange={setOpacity}
                />
                <RangeField
                  label="模糊"
                  value={blur}
                  min={0}
                  max={20}
                  suffix="px"
                  onChange={setBlur}
                />
              </div>
            ) : null}
          </>
        )}
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {dirty ? "存在未保存修改" : "配置已同步"}
        </span>
        <div className="flex items-center gap-1.5">
          <Button
            size="sm"
            variant="ghost"
            disabled={!data || (data.type === "none" && !dirty)}
            loading={reset.isPending}
            onClick={() => reset.mutate()}
          >
            <RotateCcw className="h-3.5 w-3.5" />
            恢复默认
          </Button>
          <Button
            size="sm"
            variant="primary"
            disabled={!data || !dirty || !valid}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            <Save className="h-3.5 w-3.5" />
            保存
          </Button>
        </div>
      </CardFooter>
    </Card>
  );
}
