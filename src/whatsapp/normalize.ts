import { normalizeE164 } from "../utils.js";

/**
 * WhatsApp 用户 JID（用户标识符）的正则表达式
 * 格式：电话号码@ s.whatsapp.net，如 "41796666864:0@s.whatsapp.net"
 * 其中 :0 表示设备后缀
 */
const WHATSAPP_USER_JID_RE = /^(\d+)(?::\d+)?@s\.whatsapp\.net$/i;

/**
 * WhatsApp LID（本地标识符）的正则表达式
 * 格式：电话号码@lid，如 "123456@lid"
 */
const WHATSAPP_LID_RE = /^(\d+)@lid$/i;

/**
 * 移除 WhatsApp 目标地址的前缀（如 "whatsapp:" 前缀）
 * @param value - 原始输入字符串
 * @returns 移除前缀后的字符串
 */
function stripWhatsAppTargetPrefixes(value: string): string {
  let candidate = value.trim();
  // 使用无限循环持续移除前缀，直到没有变化为止
  for (;;) {
    const before = candidate;
    // 移除开头的 "whatsapp:" 前缀（不区分大小写）
    candidate = candidate.replace(/^whatsapp:/i, "").trim();
    // 如果没有变化，说明已经处理完毕
    if (candidate === before) return candidate;
  }
}

/**
 * 判断给定的值是否为 WhatsApp 群组 JID
 * 群组 JID 格式：群组ID@g.us，如 "120363401234567890@g.us"
 * @param value - 待检查的字符串
 * @returns 是否为有效的群组 JID
 */
export function isWhatsAppGroupJid(value: string): boolean {
  const candidate = stripWhatsAppTargetPrefixes(value);
  const lower = candidate.toLowerCase();
  // 必须以 "@g.us" 结尾（群组标识）
  if (!lower.endsWith("@g.us")) return false;
  // 提取本地部分（去掉 @g.us 后缀）
  const localPart = candidate.slice(0, candidate.length - "@g.us".length);
  // 本地部分不能为空或包含 @ 符号
  if (!localPart || localPart.includes("@")) return false;
  // 验证本地部分格式：纯数字，可包含连字符分隔的段
  return /^[0-9]+(-[0-9]+)*$/.test(localPart);
}

/**
 * 判断给定的值是否为 WhatsApp 用户目标地址
 * 支持两种格式：
 * 1. 用户 JID：如 "41796666864:0@s.whatsapp.net" 或 "1555123@s.whatsapp.net"
 * 2. LID：如 "123456@lid"
 * @param value - 待检查的字符串
 * @returns 是否为有效的用户目标地址
 */
export function isWhatsAppUserTarget(value: string): boolean {
  const candidate = stripWhatsAppTargetPrefixes(value);
  return WHATSAPP_USER_JID_RE.test(candidate) || WHATSAPP_LID_RE.test(candidate);
}

/**
 * 从 WhatsApp 用户 JID 中提取电话号码
 * 支持标准用户 JID 和 LID 两种格式
 * @param jid - WhatsApp 用户 JID 字符串
 * @returns 提取的电话号码，如果无法解析则返回 null
 * @example
 * // 标准用户 JID
 * extractUserJidPhone("41796666864:0@s.whatsapp.net") // 返回 "41796666864"
 * // LID 格式
 * extractUserJidPhone("123456@lid") // 返回 "123456"
 */
function extractUserJidPhone(jid: string): string | null {
  const userMatch = jid.match(WHATSAPP_USER_JID_RE);
  if (userMatch) return userMatch[1];
  const lidMatch = jid.match(WHATSAPP_LID_RE);
  if (lidMatch) return lidMatch[1];
  return null;
}

/**
 * 标准化 WhatsApp 目标地址
 * 将各种格式的 WhatsApp 目标地址转换为统一的 E.164 格式
 * @param value - 原始输入值
 * @returns 标准化后的 E.164 格式电话号码，如果无法标准化则返回 null
 *
 * 支持的输入格式：
 * - 群组 JID：如 "120363401234567890@g.us" -> 保持不变
 * - 用户 JID：如 "1555123@s.whatsapp.net" -> "+1555123"
 * - 带设备后缀的 JID：如 "41796666864:0@s.whatsapp.net" -> "+41796666864"
 * - LID：如 "123456@lid" -> "+123456789"
 * - 带前缀：如 "whatsapp:1555123@s.whatsapp.net" -> "+1555123"
 */
export function normalizeWhatsAppTarget(value: string): string | null {
  const candidate = stripWhatsAppTargetPrefixes(value);
  if (!candidate) return null;
  // 处理群组 JID，直接返回格式化的群组地址
  if (isWhatsAppGroupJid(candidate)) {
    const localPart = candidate.slice(0, candidate.length - "@g.us".length);
    return `${localPart}@g.us`;
  }
  // 处理用户 JID（如 "41796666864:0@s.whatsapp.net"）
  // 修复：JID 如 "41796666864:0@s.whatsapp.net" 应该标准化为 "+41796666864"，
  // 而不是 "+417966668640"（避免将 ":0" 错误地当作电话号码的一部分）
  if (isWhatsAppUserTarget(candidate)) {
    const phone = extractUserJidPhone(candidate);
    if (!phone) return null;
    const normalized = normalizeE164(phone);
    return normalized.length > 1 ? normalized : null;
  }
  // 如果传入的是包含 @ 符号的 JID 格式字符串但无法识别，快速失败
  // 否则 normalizeE164 会错误地将 "group:120@g.us" 当作电话号码处理
  if (candidate.includes("@")) return null;
  // 尝试将纯数字字符串标准化为 E.164 格式
  const normalized = normalizeE164(candidate);
  return normalized.length > 1 ? normalized : null;
}
