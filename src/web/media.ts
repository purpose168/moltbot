import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { logVerbose, shouldLogVerbose } from "../globals.js";
import { type MediaKind, maxBytesForKind, mediaKindFromMime } from "../media/constants.js";
import { resolveUserPath } from "../utils.js";
import { fetchRemoteMedia } from "../media/fetch.js";
import {
  convertHeicToJpeg,
  hasAlphaChannel,
  optimizeImageToPng,
  resizeToJpeg,
} from "../media/image-ops.js";
import { detectMime, extensionForMime } from "../media/mime.js";

/**
 * WhatsApp Web 媒体处理结果
 * @property buffer - 媒体文件的二进制数据
 * @property contentType - 媒体内容类型（MIME 类型）
 * @property kind - 媒体类型（如 "image"、"video" 等）
 * @property fileName - 媒体文件名（可选）
 */
export type WebMediaResult = {
  buffer: Buffer;
  contentType?: string;
  kind: MediaKind;
  fileName?: string;
};

/**
 * WhatsApp Web 媒体处理选项
 * @property maxBytes - 最大字节数限制（可选）
 * @property optimizeImages - 是否优化图片（可选，默认为 true）
 */
type WebMediaOptions = {
  maxBytes?: number;
  optimizeImages?: boolean;
};

/**
 * HEIC 格式的 MIME 类型正则表达式
 */
const HEIC_MIME_RE = /^image\/hei[cf]$/i;

/**
 * HEIC 格式的文件扩展名正则表达式
 */
const HEIC_EXT_RE = /\.(heic|heif)$/i;

/**
 * 1MB 的字节数
 */
const MB = 1024 * 1024;

/**
 * 将字节数格式化为 MB 单位的字符串
 * @param bytes - 字节数
 * @param digits - 小数位数，默认为 2
 * @returns 格式化后的字符串，如 "1.23MB"
 */
function formatMb(bytes: number, digits = 2): string {
  return (bytes / MB).toFixed(digits);
}

/**
 * 格式化大小超限错误信息
 * @param label - 媒体类型标签
 * @param cap - 大小上限（字节）
 * @param size - 实际大小（字节）
 * @returns 格式化的错误信息字符串
 */
function formatCapLimit(label: string, cap: number, size: number): string {
  return `${label} 超过 ${formatMb(cap, 0)}MB 限制（实际为 ${formatMb(size)}MB）`;
}

/**
 * 格式化压缩失败错误信息
 * @param label - 媒体类型标签
 * @param cap - 大小上限（字节）
 * @param size - 实际大小（字节）
 * @returns 格式化的错误信息字符串
 */
function formatCapReduce(label: string, cap: number, size: number): string {
  return `${label} 无法压缩到 ${formatMb(cap, 0)}MB 以下（实际为 ${formatMb(size)}MB）`;
}

/**
 * 判断是否为 HEIC 格式的媒体源
 * @param opts - 选项对象
 * @param opts.contentType - 内容类型
 * @param opts.fileName - 文件名
 * @returns 是否为 HEIC 格式
 */
function isHeicSource(opts: { contentType?: string; fileName?: string }): boolean {
  if (opts.contentType && HEIC_MIME_RE.test(opts.contentType.trim())) return true;
  if (opts.fileName && HEIC_EXT_RE.test(opts.fileName.trim())) return true;
  return false;
}

/**
 * 将文件名转换为 JPEG 格式
 * @param fileName - 原始文件名
 * @returns 转换后的 JPEG 文件名，如 "photo.jpg"
 */
function toJpegFileName(fileName?: string): string | undefined {
  if (!fileName) return undefined;
  const trimmed = fileName.trim();
  if (!trimmed) return fileName;
  const parsed = path.parse(trimmed);
  if (!parsed.ext || HEIC_EXT_RE.test(parsed.ext)) {
    return path.format({ dir: parsed.dir, name: parsed.name || trimmed, ext: ".jpg" });
  }
  return path.format({ dir: parsed.dir, name: parsed.name, ext: ".jpg" });
}

/**
 * 优化后的图片信息
 * @property buffer - 优化后的图片数据
 * @property optimizedSize - 优化后的大小（字节）
 * @property resizeSide - 调整后的边长（像素）
 * @property format - 图片格式（"jpeg" 或 "png"）
 * @property quality - 图片质量（JPEG 格式）
 * @property compressionLevel - 压缩级别（PNG 格式）
 */
type OptimizedImage = {
  buffer: Buffer;
  optimizedSize: number;
  resizeSide: number;
  format: "jpeg" | "png";
  quality?: number;
  compressionLevel?: number;
};

/**
 * 记录图片优化信息
 * @param params - 参数对象
 * @param params.originalSize - 原始大小（字节）
 * @param params.optimized - 优化后的图片信息
 */
function logOptimizedImage(params: { originalSize: number; optimized: OptimizedImage }): void {
  if (!shouldLogVerbose()) return;
  if (params.optimized.optimizedSize >= params.originalSize) return;
  if (params.optimized.format === "png") {
    logVerbose(
      `已优化 PNG 图片（保留透明度），从 ${formatMb(params.originalSize)}MB 减少到 ${formatMb(params.optimized.optimizedSize)}MB（边长≤${params.optimized.resizeSide}px）`,
    );
    return;
  }
  logVerbose(
    `已优化媒体文件，从 ${formatMb(params.originalSize)}MB 减少到 ${formatMb(params.optimized.optimizedSize)}MB（边长≤${params.optimized.resizeSide}px，质量=${params.optimized.quality}）`,
  );
}

/**
 * 优化图片，带 PNG 到 JPEG 的降级处理
 * @param params - 参数对象
 * @param params.buffer - 原始图片数据
 * @param params.cap - 大小上限（字节）
 * @param params.meta - 媒体元数据
 * @returns 优化后的图片信息
 */
async function optimizeImageWithFallback(params: {
  buffer: Buffer;
  cap: number;
  meta?: { contentType?: string; fileName?: string };
}): Promise<OptimizedImage> {
  const { buffer, cap, meta } = params;
  const isPng = meta?.contentType === "image/png" || meta?.fileName?.toLowerCase().endsWith(".png");
  const hasAlpha = isPng && (await hasAlphaChannel(buffer));

  // 如果是带透明度的 PNG，先尝试优化为 PNG
  if (hasAlpha) {
    const optimized = await optimizeImageToPng(buffer, cap);
    if (optimized.buffer.length <= cap) {
      return { ...optimized, format: "png" };
    }
    if (shouldLogVerbose()) {
      logVerbose(`带透明度的 PNG 优化后仍超过 ${formatMb(cap, 0)}MB 限制；降级为 JPEG 格式`);
    }
  }

  // 降级为 JPEG 格式
  const optimized = await optimizeImageToJpeg(buffer, cap, meta);
  return { ...optimized, format: "jpeg" };
}

/**
 * 加载 WhatsApp Web 媒体的内部实现
 * @param mediaUrl - 媒体 URL（可以是本地路径、远程 URL 或 file:// URL）
 * @param options - 选项配置
 * @returns 媒体处理结果
 *
 * @description
 * 此函数负责：
 * 1. 处理不同类型的媒体 URL
 * 2. 加载媒体数据
 * 3. 检测媒体类型
 * 4. 应用大小限制
 * 5. 优化图片（如果需要）
 * 6. 处理 HEIC 格式转换
 */
async function loadWebMediaInternal(
  mediaUrl: string,
  options: WebMediaOptions = {},
): Promise<WebMediaResult> {
  const { maxBytes, optimizeImages = true } = options;

  // 处理 file:// URL
  if (mediaUrl.startsWith("file://")) {
    try {
      mediaUrl = fileURLToPath(mediaUrl);
    } catch {
      throw new Error(`无效的 file:// URL: ${mediaUrl}`);
    }
  }

  /**
   * 优化并限制图片大小
   * @param buffer - 图片数据
   * @param cap - 大小上限
   * @param meta - 媒体元数据
   * @returns 处理后的媒体结果
   */
  const optimizeAndClampImage = async (
    buffer: Buffer,
    cap: number,
    meta?: { contentType?: string; fileName?: string },
  ) => {
    const originalSize = buffer.length;
    const optimized = await optimizeImageWithFallback({ buffer, cap, meta });
    logOptimizedImage({ originalSize, optimized });

    // 检查优化后的大小是否符合限制
    if (optimized.buffer.length > cap) {
      throw new Error(formatCapReduce("媒体", cap, optimized.buffer.length));
    }

    // 确定内容类型和文件名
    const contentType = optimized.format === "png" ? "image/png" : "image/jpeg";
    const fileName =
      optimized.format === "jpeg" && meta && isHeicSource(meta)
        ? toJpegFileName(meta.fileName)
        : meta?.fileName;

    return {
      buffer: optimized.buffer,
      contentType,
      kind: "image" as const,
      fileName,
    };
  };

  /**
   * 限制大小并完成处理
   * @param params - 媒体参数
   * @returns 处理后的媒体结果
   */
  const clampAndFinalize = async (params: {
    buffer: Buffer;
    contentType?: string;
    kind: MediaKind;
    fileName?: string;
  }): Promise<WebMediaResult> => {
    // 如果调用者明确提供了 maxBytes，使用它（用于处理大文件的通道）
    // 否则使用每种媒体类型的默认限制
    const cap = maxBytes !== undefined ? maxBytes : maxBytesForKind(params.kind);

    // 处理图片类型
    if (params.kind === "image") {
      const isGif = params.contentType === "image/gif";
      // GIF 或不需要优化的图片
      if (isGif || !optimizeImages) {
        if (params.buffer.length > cap) {
          throw new Error(formatCapLimit(isGif ? "GIF" : "媒体", cap, params.buffer.length));
        }
        return {
          buffer: params.buffer,
          contentType: params.contentType,
          kind: params.kind,
          fileName: params.fileName,
        };
      }
      // 需要优化的图片
      return {
        ...(await optimizeAndClampImage(params.buffer, cap, {
          contentType: params.contentType,
          fileName: params.fileName,
        })),
      };
    }

    // 处理非图片类型
    if (params.buffer.length > cap) {
      throw new Error(formatCapLimit("媒体", cap, params.buffer.length));
    }
    return {
      buffer: params.buffer,
      contentType: params.contentType ?? undefined,
      kind: params.kind,
      fileName: params.fileName,
    };
  };

  // 处理远程 URL
  if (/^https?:\/\//i.test(mediaUrl)) {
    const fetched = await fetchRemoteMedia({ url: mediaUrl });
    const { buffer, contentType, fileName } = fetched;
    const kind = mediaKindFromMime(contentType);
    return await clampAndFinalize({ buffer, contentType, kind, fileName });
  }

  // 处理波浪号路径（如 ~/Downloads/photo.jpg）
  if (mediaUrl.startsWith("~")) {
    mediaUrl = resolveUserPath(mediaUrl);
  }

  // 处理本地路径
  const data = await fs.readFile(mediaUrl);
  const mime = await detectMime({ buffer: data, filePath: mediaUrl });
  const kind = mediaKindFromMime(mime);
  let fileName = path.basename(mediaUrl) || undefined;
  // 如果文件名没有扩展名但有 MIME 类型，添加适当的扩展名
  if (fileName && !path.extname(fileName) && mime) {
    const ext = extensionForMime(mime);
    if (ext) fileName = `${fileName}${ext}`;
  }
  return await clampAndFinalize({
    buffer: data,
    contentType: mime,
    kind,
    fileName,
  });
}

/**
 * 加载 WhatsApp Web 媒体（带优化）
 * @param mediaUrl - 媒体 URL
 * @param maxBytes - 最大字节数限制（可选）
 * @returns 媒体处理结果
 *
 * @description
 * 此函数会自动优化图片，适用于大多数场景
 */
export async function loadWebMedia(mediaUrl: string, maxBytes?: number): Promise<WebMediaResult> {
  return await loadWebMediaInternal(mediaUrl, {
    maxBytes,
    optimizeImages: true,
  });
}

/**
 * 加载 WhatsApp Web 媒体（原始格式）
 * @param mediaUrl - 媒体 URL
 * @param maxBytes - 最大字节数限制（可选）
 * @returns 媒体处理结果
 *
 * @description
 * 此函数不会优化图片，保留原始格式，适用于需要保持原样的场景
 */
export async function loadWebMediaRaw(
  mediaUrl: string,
  maxBytes?: number,
): Promise<WebMediaResult> {
  return await loadWebMediaInternal(mediaUrl, {
    maxBytes,
    optimizeImages: false,
  });
}

/**
 * 将图片优化为 JPEG 格式
 * @param buffer - 原始图片数据
 * @param maxBytes - 大小上限（字节）
 * @param opts - 选项配置
 * @param opts.contentType - 内容类型
 * @param opts.fileName - 文件名
 * @returns 优化后的图片信息
 *
 * @description
 * 此函数会：
 * 1. 处理 HEIC 格式转换
 * 2. 尝试不同的尺寸和质量组合
 * 3. 返回符合大小限制的最优结果
 */
export async function optimizeImageToJpeg(
  buffer: Buffer,
  maxBytes: number,
  opts: { contentType?: string; fileName?: string } = {},
): Promise<{
  buffer: Buffer;
  optimizedSize: number;
  resizeSide: number;
  quality: number;
}> {
  // 尝试不同的尺寸和质量组合
  let source = buffer;

  // 处理 HEIC 格式
  if (isHeicSource(opts)) {
    try {
      source = await convertHeicToJpeg(buffer);
    } catch (err) {
      throw new Error(`HEIC 图片转换失败: ${String(err)}`);
    }
  }

  // 尝试的尺寸列表（像素）
  const sides = [2048, 1536, 1280, 1024, 800];
  // 尝试的质量列表（百分比）
  const qualities = [80, 70, 60, 50, 40];

  let smallest: {
    buffer: Buffer;
    size: number;
    resizeSide: number;
    quality: number;
  } | null = null;

  // 遍历所有尺寸和质量组合
  for (const side of sides) {
    for (const quality of qualities) {
      try {
        const out = await resizeToJpeg({
          buffer: source,
          maxSide: side,
          quality,
          withoutEnlargement: true,
        });
        const size = out.length;

        // 记录最小的结果
        if (!smallest || size < smallest.size) {
          smallest = { buffer: out, size, resizeSide: side, quality };
        }

        // 如果符合大小限制，直接返回
        if (size <= maxBytes) {
          return {
            buffer: out,
            optimizedSize: size,
            resizeSide: side,
            quality,
          };
        }
      } catch {
        // 继续尝试其他组合
      }
    }
  }

  // 如果没有符合限制的结果，返回最小的结果
  if (smallest) {
    return {
      buffer: smallest.buffer,
      optimizedSize: smallest.size,
      resizeSide: smallest.resizeSide,
      quality: smallest.quality,
    };
  }

  throw new Error("图片优化失败");
}

/**
 * 导出 PNG 图片优化函数
 */
export { optimizeImageToPng };
