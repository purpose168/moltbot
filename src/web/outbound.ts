import { randomUUID } from "node:crypto";

import { getChildLogger } from "../logging/logger.js";
import { createSubsystemLogger } from "../logging/subsystem.js";
import { normalizePollInput, type PollInput } from "../polls.js";
import { toWhatsappJid } from "../utils.js";
import { loadConfig } from "../config/config.js";
import { resolveMarkdownTableMode } from "../config/markdown-tables.js";
import { convertMarkdownTables } from "../markdown/tables.js";
import { type ActiveWebSendOptions, requireActiveWebListener } from "./active-listener.js";
import { loadWebMedia } from "./media.js";

const outboundLog = createSubsystemLogger("gateway/channels/whatsapp").child("outbound");

/**
 * 发送 WhatsApp 消息
 *
 * @param to 接收者（电话号码或 JID）
 * @param body 消息内容
 * @param options 发送选项
 * @param options.verbose 是否启用详细日志
 * @param options.mediaUrl 媒体文件 URL（可选）
 * @param options.gifPlayback 是否启用 GIF 播放（可选）
 * @param options.accountId 账户 ID（可选）
 * @returns 包含消息 ID 和目标 JID 的对象
 */
export async function sendMessageWhatsApp(
  to: string,
  body: string,
  options: {
    verbose: boolean;
    mediaUrl?: string;
    gifPlayback?: boolean;
    accountId?: string;
  },
): Promise<{ messageId: string; toJid: string }> {
  let text = body;
  const correlationId = randomUUID();
  const startedAt = Date.now();
  const { listener: active, accountId: resolvedAccountId } = requireActiveWebListener(
    options.accountId,
  );
  const cfg = loadConfig();
  const tableMode = resolveMarkdownTableMode({
    cfg,
    channel: "whatsapp",
    accountId: resolvedAccountId ?? options.accountId,
  });
  text = convertMarkdownTables(text ?? "", tableMode);
  const logger = getChildLogger({
    module: "web-outbound",
    correlationId,
    to,
  });
  try {
    const jid = toWhatsappJid(to);
    let mediaBuffer: Buffer | undefined;
    let mediaType: string | undefined;
    if (options.mediaUrl) {
      const media = await loadWebMedia(options.mediaUrl);
      const caption = text || undefined;
      mediaBuffer = media.buffer;
      mediaType = media.contentType;
      if (media.kind === "audio") {
        // WhatsApp expects explicit opus codec for PTT voice notes.
        mediaType =
          media.contentType === "audio/ogg"
            ? "audio/ogg; codecs=opus"
            : (media.contentType ?? "application/octet-stream");
      } else if (media.kind === "video") {
        text = caption ?? "";
      } else if (media.kind === "image") {
        text = caption ?? "";
      } else {
        text = caption ?? "";
      }
    }
    outboundLog.info(`正在发送消息 -> ${jid}${options.mediaUrl ? " (媒体)" : ""}`);
    logger.info({ jid, hasMedia: Boolean(options.mediaUrl) }, "正在发送消息");
    await active.sendComposingTo(to);
    const hasExplicitAccountId = Boolean(options.accountId?.trim());
    const accountId = hasExplicitAccountId ? resolvedAccountId : undefined;
    const sendOptions: ActiveWebSendOptions | undefined =
      options.gifPlayback || accountId
        ? {
            ...(options.gifPlayback ? { gifPlayback: true } : {}),
            accountId,
          }
        : undefined;
    const result = sendOptions
      ? await active.sendMessage(to, text, mediaBuffer, mediaType, sendOptions)
      : await active.sendMessage(to, text, mediaBuffer, mediaType);
    const messageId = (result as { messageId?: string })?.messageId ?? "unknown";
    const durationMs = Date.now() - startedAt;
    outboundLog.info(
      `已发送消息 ${messageId} -> ${jid}${options.mediaUrl ? " (媒体)" : ""} (${durationMs}ms)`,
    );
    logger.info({ jid, messageId }, "已发送消息");
    return { messageId, toJid: jid };
  } catch (err) {
    logger.error(
      { err: String(err), to, hasMedia: Boolean(options.mediaUrl) },
      "通过 Web 会话发送失败",
    );
    throw err;
  }
}

/**
 * 发送 WhatsApp 消息反应（表情）
 *
 * @param chatJid 聊天 JID
 * @param messageId 消息 ID
 * @param emoji 表情符号
 * @param options 发送选项
 * @param options.verbose 是否启用详细日志
 * @param options.fromMe 是否来自当前用户（可选）
 * @param options.participant 参与者（可选）
 * @param options.accountId 账户 ID（可选）
 */
export async function sendReactionWhatsApp(
  chatJid: string,
  messageId: string,
  emoji: string,
  options: {
    verbose: boolean;
    fromMe?: boolean;
    participant?: string;
    accountId?: string;
  },
): Promise<void> {
  const correlationId = randomUUID();
  const { listener: active } = requireActiveWebListener(options.accountId);
  const logger = getChildLogger({
    module: "web-outbound",
    correlationId,
    chatJid,
    messageId,
  });
  try {
    const jid = toWhatsappJid(chatJid);
    outboundLog.info(`正在发送反应 "${emoji}" -> 消息 ${messageId}`);
    logger.info({ chatJid: jid, messageId, emoji }, "正在发送反应");
    await active.sendReaction(
      chatJid,
      messageId,
      emoji,
      options.fromMe ?? false,
      options.participant,
    );
    outboundLog.info(`已发送反应 "${emoji}" -> 消息 ${messageId}`);
    logger.info({ chatJid: jid, messageId, emoji }, "已发送反应");
  } catch (err) {
    logger.error({ err: String(err), chatJid, messageId, emoji }, "通过 Web 会话发送反应失败");
    throw err;
  }
}

/**
 * 发送 WhatsApp 投票消息
 *
 * @param to 接收者（电话号码或 JID）
 * @param poll 投票信息
 * @param options 发送选项
 * @param options.verbose 是否启用详细日志
 * @param options.accountId 账户 ID（可选）
 * @returns 包含消息 ID 和目标 JID 的对象
 */
export async function sendPollWhatsApp(
  to: string,
  poll: PollInput,
  options: { verbose: boolean; accountId?: string },
): Promise<{ messageId: string; toJid: string }> {
  const correlationId = randomUUID();
  const startedAt = Date.now();
  const { listener: active } = requireActiveWebListener(options.accountId);
  const logger = getChildLogger({
    module: "web-outbound",
    correlationId,
    to,
  });
  try {
    const jid = toWhatsappJid(to);
    const normalized = normalizePollInput(poll, { maxOptions: 12 });
    outboundLog.info(`正在发送投票 -> ${jid}: "${normalized.question}"`);
    logger.info(
      {
        jid,
        question: normalized.question,
        optionCount: normalized.options.length,
        maxSelections: normalized.maxSelections,
      },
      "正在发送投票",
    );
    const result = await active.sendPoll(to, normalized);
    const messageId = (result as { messageId?: string })?.messageId ?? "unknown";
    const durationMs = Date.now() - startedAt;
    outboundLog.info(`已发送投票 ${messageId} -> ${jid} (${durationMs}ms)`);
    logger.info({ jid, messageId }, "已发送投票");
    return { messageId, toJid: jid };
  } catch (err) {
    logger.error({ err: String(err), to, question: poll.question }, "通过 Web 会话发送投票失败");
    throw err;
  }
}
