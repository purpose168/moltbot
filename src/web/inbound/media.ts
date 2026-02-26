/**
 * WhatsApp Web 入站媒体处理模块
 *
 * 此模块负责处理 WhatsApp Web 入站媒体消息的下载和处理，
 * 支持图片、视频、文档、音频和贴纸等多种媒体类型。
 */
import type { proto, WAMessage } from "@whiskeysockets/baileys";
import { downloadMediaMessage, normalizeMessageContent } from "@whiskeysockets/baileys";
import { logVerbose } from "../../globals.js";
import type { createWaSocket } from "../session.js";

/**
 * 解包消息，处理消息内容的标准化
 *
 * @param message - 原始消息对象
 * @returns 标准化后的消息对象
 */
function unwrapMessage(message: proto.IMessage | undefined): proto.IMessage | undefined {
  const normalized = normalizeMessageContent(message as proto.IMessage | undefined);
  return normalized as proto.IMessage | undefined;
}

/**
 * 下载入站媒体消息
 *
 * @param msg - 原始 Web 消息信息
 * @param sock - WhatsApp Web 套接字实例
 * @returns 包含媒体缓冲区和 MIME 类型的对象，如果不是媒体消息或下载失败则返回 undefined
 *
 * @description
 * 此函数会：
 * 1. 检查消息是否包含媒体内容
 * 2. 提取媒体的 MIME 类型
 * 3. 下载媒体内容到缓冲区
 * 4. 返回媒体缓冲区和 MIME 类型
 */
export async function downloadInboundMedia(
  msg: proto.IWebMessageInfo,
  sock: Awaited<ReturnType<typeof createWaSocket>>,
): Promise<{ buffer: Buffer; mimetype?: string } | undefined> {
  // 解包并标准化消息
  const message = unwrapMessage(msg.message as proto.IMessage | undefined);
  if (!message) return undefined;

  // 提取媒体的 MIME 类型
  const mimetype =
    message.imageMessage?.mimetype ??
    message.videoMessage?.mimetype ??
    message.documentMessage?.mimetype ??
    message.audioMessage?.mimetype ??
    message.stickerMessage?.mimetype ??
    undefined;

  // 检查是否为媒体消息
  if (
    !message.imageMessage &&
    !message.videoMessage &&
    !message.documentMessage &&
    !message.audioMessage &&
    !message.stickerMessage
  ) {
    return undefined;
  }

  try {
    // 下载媒体消息到缓冲区
    const buffer = (await downloadMediaMessage(
      msg as WAMessage,
      "buffer",
      {},
      {
        reuploadRequest: sock.updateMediaMessage,
        logger: sock.logger,
      },
    )) as Buffer;

    return { buffer, mimetype };
  } catch (err) {
    logVerbose(`下载媒体消息失败: ${String(err)}`);
    return undefined;
  }
}
