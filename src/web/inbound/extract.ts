/**
 * WhatsApp Web 消息提取模块
 *
 * 此模块负责从 WhatsApp Web 消息中提取各种类型的数据，
 * 包括文本、位置、媒体占位符、提及的用户、联系人信息等。
 */
import type { proto } from "@whiskeysockets/baileys";
import {
  extractMessageContent,
  getContentType,
  normalizeMessageContent,
} from "@whiskeysockets/baileys";
import { formatLocationText, type NormalizedLocation } from "../../channels/location.js";
import { logVerbose } from "../../globals.js";
import { jidToE164 } from "../../utils.js";
import { parseVcard } from "../vcard.js";

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
 * 从消息中提取上下文信息
 *
 * @param message - 消息对象
 * @returns 上下文信息对象，如果不存在则返回 undefined
 *
 * @description
 * 此函数会：
 * 1. 尝试从消息的主要内容类型中提取上下文信息
 * 2. 如果失败，尝试从各种消息类型的上下文中查找
 * 3. 如果仍失败，遍历消息对象的所有值查找上下文信息
 */
function extractContextInfo(message: proto.IMessage | undefined): proto.IContextInfo | undefined {
  if (!message) return undefined;
  const contentType = getContentType(message);
  const candidate = contentType ? (message as Record<string, unknown>)[contentType] : undefined;
  const contextInfo =
    candidate && typeof candidate === "object" && "contextInfo" in candidate
      ? (candidate as { contextInfo?: proto.IContextInfo }).contextInfo
      : undefined;
  if (contextInfo) return contextInfo;

  // 从各种消息类型中查找上下文信息
  const fallback =
    message.extendedTextMessage?.contextInfo ??
    message.imageMessage?.contextInfo ??
    message.videoMessage?.contextInfo ??
    message.documentMessage?.contextInfo ??
    message.audioMessage?.contextInfo ??
    message.stickerMessage?.contextInfo ??
    message.buttonsResponseMessage?.contextInfo ??
    message.listResponseMessage?.contextInfo ??
    message.templateButtonReplyMessage?.contextInfo ??
    message.interactiveResponseMessage?.contextInfo ??
    message.buttonsMessage?.contextInfo ??
    message.listMessage?.contextInfo;
  if (fallback) return fallback;

  // 遍历消息对象的所有值查找上下文信息
  for (const value of Object.values(message)) {
    if (!value || typeof value !== "object") continue;
    if (!("contextInfo" in value)) continue;
    const candidateContext = (value as { contextInfo?: proto.IContextInfo }).contextInfo;
    if (candidateContext) return candidateContext;
  }
  return undefined;
}

/**
 * 从消息中提取被提及的 JID 列表
 *
 * @param rawMessage - 原始消息对象
 * @returns 被提及的 JID 列表，如果没有则返回 undefined
 *
 * @description
 * 此函数会从消息的各种可能位置提取被提及的用户 JID
 */
export function extractMentionedJids(rawMessage: proto.IMessage | undefined): string[] | undefined {
  const message = unwrapMessage(rawMessage);
  if (!message) return undefined;

  const candidates: Array<string[] | null | undefined> = [
    message.extendedTextMessage?.contextInfo?.mentionedJid,
    message.extendedTextMessage?.contextInfo?.quotedMessage?.extendedTextMessage?.contextInfo
      ?.mentionedJid,
    message.imageMessage?.contextInfo?.mentionedJid,
    message.videoMessage?.contextInfo?.mentionedJid,
    message.documentMessage?.contextInfo?.mentionedJid,
    message.audioMessage?.contextInfo?.mentionedJid,
    message.stickerMessage?.contextInfo?.mentionedJid,
    message.buttonsResponseMessage?.contextInfo?.mentionedJid,
    message.listResponseMessage?.contextInfo?.mentionedJid,
  ];

  const flattened = candidates.flatMap((arr) => arr ?? []).filter(Boolean);
  if (flattened.length === 0) return undefined;
  return Array.from(new Set(flattened)); // 去重
}

/**
 * 从消息中提取文本内容
 *
 * @param rawMessage - 原始消息对象
 * @returns 提取的文本内容，如果没有则返回 undefined
 *
 * @description
 * 此函数会：
 * 1. 尝试从消息的 conversation 字段提取
 * 2. 尝试从 extendedTextMessage.text 提取
 * 3. 尝试从各种媒体消息的 caption 提取
 * 4. 尝试从联系人消息中生成占位符
 */
export function extractText(rawMessage: proto.IMessage | undefined): string | undefined {
  const message = unwrapMessage(rawMessage);
  if (!message) return undefined;
  const extracted = extractMessageContent(message);
  const candidates = [message, extracted && extracted !== message ? extracted : undefined];

  for (const candidate of candidates) {
    if (!candidate) continue;
    // 从 conversation 字段提取
    if (typeof candidate.conversation === "string" && candidate.conversation.trim()) {
      return candidate.conversation.trim();
    }
    // 从 extendedTextMessage 提取
    const extended = candidate.extendedTextMessage?.text;
    if (extended?.trim()) return extended.trim();
    // 从媒体消息的 caption 提取
    const caption =
      candidate.imageMessage?.caption ??
      candidate.videoMessage?.caption ??
      candidate.documentMessage?.caption;
    if (caption?.trim()) return caption.trim();
  }

  // 从联系人消息生成占位符
  const contactPlaceholder =
    extractContactPlaceholder(message) ??
    (extracted && extracted !== message
      ? extractContactPlaceholder(extracted as proto.IMessage | undefined)
      : undefined);
  if (contactPlaceholder) return contactPlaceholder;
  return undefined;
}

/**
 * 为媒体消息生成占位符文本
 *
 * @param rawMessage - 原始消息对象
 * @returns 媒体占位符文本，如果不是媒体消息则返回 undefined
 *
 * @description
 * 根据消息类型返回不同的占位符：
 * - 图片：<media:image>
 * - 视频：<media:video>
 * - 音频：<media:audio>
 * - 文档：<media:document>
 * - 贴纸：<media:sticker>
 */
export function extractMediaPlaceholder(
  rawMessage: proto.IMessage | undefined,
): string | undefined {
  const message = unwrapMessage(rawMessage);
  if (!message) return undefined;
  if (message.imageMessage) return "<media:image>";
  if (message.videoMessage) return "<media:video>";
  if (message.audioMessage) return "<media:audio>";
  if (message.documentMessage) return "<media:document>";
  if (message.stickerMessage) return "<media:sticker>";
  return undefined;
}

/**
 * 为联系人消息生成占位符文本
 *
 * @param rawMessage - 原始消息对象
 * @returns 联系人占位符文本，如果不是联系人消息则返回 undefined
 */
function extractContactPlaceholder(rawMessage: proto.IMessage | undefined): string | undefined {
  const message = unwrapMessage(rawMessage);
  if (!message) return undefined;

  // 处理单个联系人消息
  const contact = message.contactMessage ?? undefined;
  if (contact) {
    const { name, phones } = describeContact({
      displayName: contact.displayName,
      vcard: contact.vcard,
    });
    return formatContactPlaceholder(name, phones);
  }

  // 处理多个联系人消息
  const contactsArray = message.contactsArrayMessage?.contacts ?? undefined;
  if (!contactsArray || contactsArray.length === 0) return undefined;
  const labels = contactsArray
    .map((entry) => describeContact({ displayName: entry.displayName, vcard: entry.vcard }))
    .map((entry) => formatContactLabel(entry.name, entry.phones))
    .filter((value): value is string => Boolean(value));
  return formatContactsPlaceholder(labels, contactsArray.length);
}

/**
 * 描述联系人信息
 *
 * @param input - 联系人输入信息
 * @param input.displayName - 显示名称
 * @param input.vcard - vCard 数据
 * @returns 联系人描述对象，包含姓名和电话号码
 */
function describeContact(input: { displayName?: string | null; vcard?: string | null }): {
  name?: string;
  phones: string[];
} {
  const displayName = (input.displayName ?? "").trim();
  const parsed = parseVcard(input.vcard ?? undefined);
  const name = displayName || parsed.name;
  return { name, phones: parsed.phones };
}

/**
 * 格式化单个联系人占位符
 *
 * @param name - 联系人姓名
 * @param phones - 电话号码列表
 * @returns 格式化的联系人占位符
 */
function formatContactPlaceholder(name?: string, phones?: string[]): string {
  const label = formatContactLabel(name, phones);
  if (!label) return "<contact>";
  return `<contact: ${label}>`;
}

/**
 * 格式化多个联系人占位符
 *
 * @param labels - 联系人标签列表
 * @param total - 总联系人数量
 * @returns 格式化的联系人占位符
 */
function formatContactsPlaceholder(labels: string[], total: number): string {
  const cleaned = labels.map((label) => label.trim()).filter(Boolean);
  if (cleaned.length === 0) {
    const suffix = total === 1 ? "contact" : "contacts";
    return `<contacts: ${total} ${suffix}>`;
  }
  const remaining = Math.max(total - cleaned.length, 0);
  const suffix = remaining > 0 ? ` +${remaining} more` : "";
  return `<contacts: ${cleaned.join(", ")}${suffix}>`;
}

/**
 * 格式化联系人标签
 *
 * @param name - 联系人姓名
 * @param phones - 电话号码列表
 * @returns 格式化的联系人标签，如果没有信息则返回 undefined
 */
function formatContactLabel(name?: string, phones?: string[]): string | undefined {
  const phoneLabel = formatPhoneList(phones);
  const parts = [name, phoneLabel].filter((value): value is string => Boolean(value));
  if (parts.length === 0) return undefined;
  return parts.join(", ");
}

/**
 * 格式化电话号码列表
 *
 * @param phones - 电话号码列表
 * @returns 格式化的电话号码标签，如果没有电话则返回 undefined
 *
 * @description
 * 只显示第一个电话号码，其余用 " +N more" 表示
 */
function formatPhoneList(phones?: string[]): string | undefined {
  const cleaned = phones?.map((phone) => phone.trim()).filter(Boolean) ?? [];
  if (cleaned.length === 0) return undefined;
  const { shown, remaining } = summarizeList(cleaned, cleaned.length, 1);
  const [primary] = shown;
  if (!primary) return undefined;
  if (remaining === 0) return primary;
  return `${primary} (+${remaining} more)`;
}

/**
 * 摘要列表，只显示部分项
 *
 * @param values - 值列表
 * @param total - 总数量
 * @param maxShown - 最大显示数量
 * @returns 显示的项和剩余数量
 */
function summarizeList(
  values: string[],
  total: number,
  maxShown: number,
): { shown: string[]; remaining: number } {
  const shown = values.slice(0, maxShown);
  const remaining = Math.max(total - shown.length, 0);
  return { shown, remaining };
}

/**
 * 从消息中提取位置数据
 *
 * @param rawMessage - 原始消息对象
 * @returns 标准化的位置信息，如果不是位置消息则返回 null
 *
 * @description
 * 此函数会处理：
 * 1. 实时位置消息（liveLocationMessage）
 * 2. 普通位置消息（locationMessage）
 * 并返回标准化的位置对象
 */
export function extractLocationData(
  rawMessage: proto.IMessage | undefined,
): NormalizedLocation | null {
  const message = unwrapMessage(rawMessage);
  if (!message) return null;

  // 处理实时位置消息
  const live = message.liveLocationMessage ?? undefined;
  if (live) {
    const latitudeRaw = live.degreesLatitude;
    const longitudeRaw = live.degreesLongitude;
    if (latitudeRaw != null && longitudeRaw != null) {
      const latitude = Number(latitudeRaw);
      const longitude = Number(longitudeRaw);
      if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
        return {
          latitude,
          longitude,
          accuracy: live.accuracyInMeters ?? undefined,
          caption: live.caption ?? undefined,
          source: "live",
          isLive: true,
        };
      }
    }
  }

  // 处理普通位置消息
  const location = message.locationMessage ?? undefined;
  if (location) {
    const latitudeRaw = location.degreesLatitude;
    const longitudeRaw = location.degreesLongitude;
    if (latitudeRaw != null && longitudeRaw != null) {
      const latitude = Number(latitudeRaw);
      const longitude = Number(longitudeRaw);
      if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
        const isLive = Boolean(location.isLive);
        return {
          latitude,
          longitude,
          accuracy: location.accuracyInMeters ?? undefined,
          name: location.name ?? undefined,
          address: location.address ?? undefined,
          caption: location.comment ?? undefined,
          source: isLive ? "live" : location.name || location.address ? "place" : "pin",
          isLive,
        };
      }
    }
  }

  return null;
}

/**
 * 描述回复消息的上下文信息
 *
 * @param rawMessage - 原始消息对象
 * @returns 回复上下文信息，如果不是回复消息则返回 null
 *
 * @description
 * 此函数会提取：
 * 1. 被回复消息的 ID
 * 2. 被回复消息的内容（文本、位置或媒体占位符）
 * 3. 被回复消息的发件人信息
 */
export function describeReplyContext(rawMessage: proto.IMessage | undefined): {
  id?: string;
  body: string;
  sender: string;
  senderJid?: string;
  senderE164?: string;
} | null {
  const message = unwrapMessage(rawMessage);
  if (!message) return null;
  const contextInfo = extractContextInfo(message);
  const quoted = normalizeMessageContent(
    contextInfo?.quotedMessage as proto.IMessage | undefined,
  ) as proto.IMessage | undefined;
  if (!quoted) return null;

  // 提取位置信息
  const location = extractLocationData(quoted);
  const locationText = location ? formatLocationText(location) : undefined;
  // 提取文本内容
  const text = extractText(quoted);
  // 组合消息内容
  let body: string | undefined = [text, locationText].filter(Boolean).join("\n").trim();
  if (!body) body = extractMediaPlaceholder(quoted);
  if (!body) {
    const quotedType = quoted ? getContentType(quoted) : undefined;
    logVerbose(`引用消息缺少可提取内容${quotedType ? ` (类型 ${quotedType})` : ""}`);
    return null;
  }

  // 提取发件人信息
  const senderJid = contextInfo?.participant ?? undefined;
  const senderE164 = senderJid ? (jidToE164(senderJid) ?? senderJid) : undefined;
  const sender = senderE164 ?? "未知发件人";

  return {
    id: contextInfo?.stanzaId ? String(contextInfo.stanzaId) : undefined,
    body,
    sender,
    senderJid,
    senderE164,
  };
}
