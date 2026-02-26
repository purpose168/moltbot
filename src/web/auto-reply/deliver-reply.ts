import { chunkMarkdownTextWithMode, type ChunkMode } from "../../auto-reply/chunk.js";
import type { MarkdownTableMode } from "../../config/types.base.js";
import { convertMarkdownTables } from "../../markdown/tables.js";
import type { ReplyPayload } from "../../auto-reply/types.js";
import { logVerbose, shouldLogVerbose } from "../../globals.js";
import { loadWebMedia } from "../media.js";
import { newConnectionId } from "../reconnect.js";
import { formatError } from "../session.js";
import { whatsappOutboundLog } from "./loggers.js";
import type { WebInboundMsg } from "./types.js";
import { elide } from "./util.js";

/**
 * 发送 WhatsApp Web 自动回复
 *
 * 此函数处理自动回复的发送逻辑，支持以下功能：
 * 1. 文本回复（支持长文本分块）
 * 2. 媒体回复（图片、音频、视频、文档）
 * 3. 错误处理和网络异常重试
 * 4. 详细的日志记录
 * 5. 媒体发送失败时的文本回退
 *
 * @param params - 回复参数
 * @param params.replyResult - 回复内容和媒体信息
 * @param params.msg - 入站消息对象，包含回复方法
 * @param params.maxMediaBytes - 媒体文件大小限制
 * @param params.textLimit - 文本消息长度限制
 * @param params.chunkMode - 文本分块模式
 * @param params.replyLogger - 回复日志记录器
 * @param params.connectionId - 连接 ID
 * @param params.skipLog - 是否跳过日志记录
 * @param params.tableMode - Markdown 表格转换模式
 */
export async function deliverWebReply(params: {
  replyResult: ReplyPayload;
  msg: WebInboundMsg;
  maxMediaBytes: number;
  textLimit: number;
  chunkMode?: ChunkMode;
  replyLogger: {
    info: (obj: unknown, msg: string) => void;
    warn: (obj: unknown, msg: string) => void;
  };
  connectionId?: string;
  skipLog?: boolean;
  tableMode?: MarkdownTableMode;
}) {
  const { replyResult, msg, maxMediaBytes, textLimit, replyLogger, connectionId, skipLog } = params;
  const replyStarted = Date.now();
  const tableMode = params.tableMode ?? "code";
  const chunkMode = params.chunkMode ?? "length";

  // 转换 Markdown 表格为适合 WhatsApp 的格式
  const convertedText = convertMarkdownTables(replyResult.text || "", tableMode);

  // 将文本分块以适应 WhatsApp 消息长度限制
  const textChunks = chunkMarkdownTextWithMode(convertedText, textLimit, chunkMode);

  // 处理媒体 URL，支持单个媒体 URL 或多个媒体 URL 数组
  const mediaList = replyResult.mediaUrls?.length
    ? replyResult.mediaUrls
    : replyResult.mediaUrl
      ? [replyResult.mediaUrl]
      : [];

  /**
   * 延迟函数，用于重试机制中的退避策略
   * @param ms - 延迟毫秒数
   */
  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  /**
   * 带重试机制的发送函数
   *
   * 当遇到网络错误（如连接关闭、重置、超时等）时，会自动重试
   * 使用指数退避策略，每次重试间隔增加
   *
   * @param fn - 要执行的发送函数
   * @param label - 操作标签，用于日志记录
   * @param maxAttempts - 最大重试次数
   */
  const sendWithRetry = async (fn: () => Promise<unknown>, label: string, maxAttempts = 3) => {
    let lastErr: unknown;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (err) {
        lastErr = err;
        const errText = formatError(err);
        const isLast = attempt === maxAttempts;

        // 检查是否应该重试（网络连接相关错误）
        const shouldRetry = /closed|reset|timed\\s*out|disconnect/i.test(errText);
        if (!shouldRetry || isLast) {
          throw err;
        }

        // 指数退避策略
        const backoffMs = 500 * attempt;
        logVerbose(
          `重试 ${label} 发送到 ${msg.from}，失败后 (${attempt}/${maxAttempts - 1}) 在 ${backoffMs}ms 后重试: ${errText}`,
        );
        await sleep(backoffMs);
      }
    }
    throw lastErr;
  };

  // 纯文本回复处理
  if (mediaList.length === 0 && textChunks.length) {
    const totalChunks = textChunks.length;
    for (const [index, chunk] of textChunks.entries()) {
      const chunkStarted = Date.now();
      await sendWithRetry(() => msg.reply(chunk), "text");

      // 记录每个文本块的发送时间
      if (!skipLog) {
        const durationMs = Date.now() - chunkStarted;
        whatsappOutboundLog.debug(
          `已发送文本块 ${index + 1}/${totalChunks} 到 ${msg.from} (${durationMs.toFixed(0)}ms)`,
        );
      }
    }

    // 记录完整的文本回复信息
    replyLogger.info(
      {
        correlationId: msg.id ?? newConnectionId(),
        connectionId: connectionId ?? null,
        to: msg.from,
        from: msg.to,
        text: elide(replyResult.text, 240),
        mediaUrl: null,
        mediaSizeBytes: null,
        mediaKind: null,
        durationMs: Date.now() - replyStarted,
      },
      "auto-reply sent (text)",
    );
    return;
  }

  // 处理包含媒体的回复
  const remainingText = [...textChunks];

  // 媒体回复处理（第一个媒体可以带标题）
  for (const [index, mediaUrl] of mediaList.entries()) {
    // 只为第一个媒体添加标题（从文本块中取出）
    const caption = index === 0 ? remainingText.shift() || undefined : undefined;
    try {
      // 加载媒体文件并进行大小限制检查
      const media = await loadWebMedia(mediaUrl, maxMediaBytes);

      // 详细日志记录
      if (shouldLogVerbose()) {
        logVerbose(`Web 自动回复媒体大小: ${(media.buffer.length / (1024 * 1024)).toFixed(2)}MB`);
        logVerbose(`Web 自动回复媒体来源: ${mediaUrl} (类型 ${media.kind})`);
      }

      // 根据媒体类型发送不同的消息
      if (media.kind === "image") {
        await sendWithRetry(
          () =>
            msg.sendMedia({
              image: media.buffer,
              caption,
              mimetype: media.contentType,
            }),
          "media:image",
        );
      } else if (media.kind === "audio") {
        await sendWithRetry(
          () =>
            msg.sendMedia({
              audio: media.buffer,
              ptt: true, // 设为 true 表示语音消息
              mimetype: media.contentType,
              caption,
            }),
          "media:audio",
        );
      } else if (media.kind === "video") {
        await sendWithRetry(
          () =>
            msg.sendMedia({
              video: media.buffer,
              caption,
              mimetype: media.contentType,
            }),
          "media:video",
        );
      } else {
        // 处理其他类型的媒体（文档）
        const fileName = media.fileName ?? mediaUrl.split("/").pop() ?? "file";
        const mimetype = media.contentType ?? "application/octet-stream";
        await sendWithRetry(
          () =>
            msg.sendMedia({
              document: media.buffer,
              fileName,
              caption,
              mimetype,
            }),
          "media:document",
        );
      }

      // 记录媒体发送成功
      whatsappOutboundLog.info(
        `已发送媒体回复到 ${msg.from} (${(media.buffer.length / (1024 * 1024)).toFixed(2)}MB)`,
      );
      replyLogger.info(
        {
          correlationId: msg.id ?? newConnectionId(),
          connectionId: connectionId ?? null,
          to: msg.from,
          from: msg.to,
          text: caption ?? null,
          mediaUrl,
          mediaSizeBytes: media.buffer.length,
          mediaKind: media.kind,
          durationMs: Date.now() - replyStarted,
        },
        "auto-reply sent (media)",
      );
    } catch (err) {
      // 处理媒体发送失败
      whatsappOutboundLog.error(`发送 Web 媒体到 ${msg.from} 失败: ${formatError(err)}`);
      replyLogger.warn({ err, mediaUrl }, "发送 Web 媒体回复失败");

      // 对于第一个媒体失败，发送文本回退
      if (index === 0) {
        const warning =
          err instanceof Error ? `⚠️ 媒体发送失败: ${err.message}` : "⚠️ 媒体发送失败.";
        const fallbackTextParts = [remainingText.shift() ?? caption ?? "", warning].filter(Boolean);
        const fallbackText = fallbackTextParts.join("\n");
        if (fallbackText) {
          whatsappOutboundLog.warn(`媒体发送跳过; 仅发送文本到 ${msg.from}`);
          await msg.reply(fallbackText);
        }
      }
    }
  }

  // 发送媒体后剩余的文本块
  for (const chunk of remainingText) {
    await msg.reply(chunk);
  }
}
