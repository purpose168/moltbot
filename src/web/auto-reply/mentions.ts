/**
 * Web 自动回复提及处理模块
 *
 * @description
 * 此模块用于处理 WhatsApp Web 消息中的提及功能，
 * 支持检测机器人是否被提及、解析提及目标、
 * 构建提及配置等核心功能，
 * 是群组消息处理和权限控制的重要组成部分。
 */

import { buildMentionRegexes, normalizeMentionText } from "../../auto-reply/reply/mentions.js";
import type { loadConfig } from "../../config/config.js";
import { isSelfChatMode, jidToE164, normalizeE164 } from "../../utils.js";
import type { WebInboundMsg } from "./types.js";

/**
 * 提及配置类型
 *
 * @description
 * 定义了提及功能的配置结构，
 * 包含用于匹配提及的正则表达式和允许的发送者列表。
 */
export type MentionConfig = {
  /** 用于匹配提及的正则表达式数组 */
  mentionRegexes: RegExp[];
  /** 允许的发送者列表 */
  allowFrom?: Array<string | number>;
};

/**
 * 提及目标类型
 *
 * @description
 * 定义了提及目标的信息结构，
 * 包含标准化后的提及列表、机器人自身的 E.164 格式号码和 JID。
 */
export type MentionTargets = {
  /** 标准化后的提及列表（E.164 格式或原始 JID） */
  normalizedMentions: string[];
  /** 机器人自身的 E.164 格式号码 */
  selfE164: string | null;
  /** 机器人自身的 JID（去除端口号） */
  selfJid: string | null;
};

/**
 * 构建提及配置
 *
 * @description
 * 根据应用配置和可选的代理 ID，构建提及功能的配置，
 * 生成用于匹配提及的正则表达式，并获取 WhatsApp 通道的允许列表。
 *
 * @param cfg - 应用配置对象
 * @param agentId - 可选的代理 ID
 * @returns 提及配置对象
 */
export function buildMentionConfig(
  cfg: ReturnType<typeof loadConfig>,
  agentId?: string,
): MentionConfig {
  // 构建提及正则表达式
  const mentionRegexes = buildMentionRegexes(cfg, agentId);
  // 返回配置对象
  return { mentionRegexes, allowFrom: cfg.channels?.whatsapp?.allowFrom };
}

/**
 * 解析提及目标
 *
 * @description
 * 从入站消息中解析提及目标信息，
 * 包括标准化提及的 JID 为 E.164 格式，
 * 以及获取机器人自身的 E.164 格式号码和 JID。
 *
 * @param msg - 入站消息对象
 * @param authDir - 可选的认证目录，用于 JID 解析
 * @returns 提及目标信息
 */
export function resolveMentionTargets(msg: WebInboundMsg, authDir?: string): MentionTargets {
  // 构建 JID 解析选项
  const jidOptions = authDir ? { authDir } : undefined;

  // 标准化提及的 JID
  const normalizedMentions = msg.mentionedJids?.length
    ? msg.mentionedJids.map((jid) => jidToE164(jid, jidOptions) ?? jid).filter(Boolean)
    : [];

  // 获取机器人自身的 E.164 格式号码
  const selfE164 = msg.selfE164 ?? (msg.selfJid ? jidToE164(msg.selfJid, jidOptions) : null);

  // 获取机器人自身的 JID（去除端口号）
  const selfJid = msg.selfJid ? msg.selfJid.replace(/:\d+/, "") : null;

  return { normalizedMentions, selfE164, selfJid };
}

/**
 * 检测机器人是否被提及
 *
 * @description
 * 检测消息是否提及了机器人，支持多种检测方式：
 * 1. 直接提及检测 - 检查消息中是否直接提及了机器人的 JID
 * 2. 文本提及检测 - 检查消息内容是否匹配提及正则表达式
 * 3. 号码提及检测 - 检查消息体是否包含机器人的电话号码
 * 4. 自聊模式处理 - 自聊模式下的特殊处理
 *
 * @param msg - 入站消息对象
 * @param mentionCfg - 提及配置
 * @param targets - 提及目标信息
 * @returns 是否被提及
 */
export function isBotMentionedFromTargets(
  msg: WebInboundMsg,
  mentionCfg: MentionConfig,
  targets: MentionTargets,
): boolean {
  // 清理文本，移除 WhatsApp 在显示名称周围注入的零宽和方向标记
  const clean = (text: string) => normalizeMentionText(text);

  // 检查是否为自聊模式
  const isSelfChat = isSelfChatMode(targets.selfE164, mentionCfg.allowFrom);

  // 检查是否有提及
  const hasMentions = (msg.mentionedJids?.length ?? 0) > 0;

  // 非自聊模式下的直接提及检测
  if (hasMentions && !isSelfChat) {
    // 检查是否直接提及了机器人的 E.164 号码
    if (targets.selfE164 && targets.normalizedMentions.includes(targets.selfE164)) return true;

    // 检查是否直接提及了机器人的 JID
    if (targets.selfJid) {
      // 有些提及使用裸 JID；为安全起见，匹配 E.164
      if (targets.normalizedMentions.includes(targets.selfJid)) return true;
    }

    // 如果消息明确提及了其他人，不要回退到正则表达式匹配
    return false;
  } else if (hasMentions && isSelfChat) {
    // 自聊模式：忽略 WhatsApp @提及 JID，否则在群组聊天中 @提及所有者会触发机器人
  }

  // 文本提及检测：检查消息内容是否匹配提及正则表达式
  const bodyClean = clean(msg.body);
  if (mentionCfg.mentionRegexes.some((re) => re.test(bodyClean))) return true;

  // 回退：检测消息体是否包含机器人自己的号码（带或不带 +，带或不带空格）
  if (targets.selfE164) {
    // 提取号码的数字部分
    const selfDigits = targets.selfE164.replace(/\D/g, "");
    if (selfDigits) {
      // 检查消息中的数字是否包含机器人号码的数字
      const bodyDigits = bodyClean.replace(/[^\d]/g, "");
      if (bodyDigits.includes(selfDigits)) return true;

      // 检查消息中是否包含机器人号码（带或不带空格）
      const bodyNoSpace = msg.body.replace(/[\s-]/g, "");
      const pattern = new RegExp(`\\+?${selfDigits}`, "i");
      if (pattern.test(bodyNoSpace)) return true;
    }
  }

  return false;
}

/**
 * 调试提及信息
 *
 * @description
 * 生成提及检测的详细调试信息，
 * 包括消息来源、内容、提及的 JID、机器人自身信息等，
 * 用于排查提及功能的问题。
 *
 * @param msg - 入站消息对象
 * @param mentionCfg - 提及配置
 * @param authDir - 可选的认证目录，用于 JID 解析
 * @returns 提及检测结果和详细信息
 */
export function debugMention(
  msg: WebInboundMsg,
  mentionCfg: MentionConfig,
  authDir?: string,
): { wasMentioned: boolean; details: Record<string, unknown> } {
  // 解析提及目标
  const mentionTargets = resolveMentionTargets(msg, authDir);

  // 检测是否被提及
  const result = isBotMentionedFromTargets(msg, mentionCfg, mentionTargets);

  // 构建详细信息
  const details = {
    from: msg.from,
    body: msg.body,
    bodyClean: normalizeMentionText(msg.body),
    mentionedJids: msg.mentionedJids ?? null,
    normalizedMentionedJids: mentionTargets.normalizedMentions.length
      ? mentionTargets.normalizedMentions
      : null,
    selfJid: msg.selfJid ?? null,
    selfJidBare: mentionTargets.selfJid,
    selfE164: msg.selfE164 ?? null,
    resolvedSelfE164: mentionTargets.selfE164,
  };

  return { wasMentioned: result, details };
}

/**
 * 解析所有者列表
 *
 * @description
 * 从提及配置中解析标准化的所有者列表，
 * 如果没有配置允许列表，则使用机器人自身的号码作为默认值。
 *
 * @param mentionCfg - 提及配置
 * @param selfE164 - 机器人自身的 E.164 格式号码
 * @returns 标准化后的所有者列表
 */
export function resolveOwnerList(mentionCfg: MentionConfig, selfE164?: string | null) {
  const allowFrom = mentionCfg.allowFrom;

  // 构建原始列表：优先使用配置的允许列表，否则使用机器人自身号码
  const raw =
    Array.isArray(allowFrom) && allowFrom.length > 0 ? allowFrom : selfE164 ? [selfE164] : [];

  // 标准化列表：过滤空值和通配符，转换为 E.164 格式
  return raw
    .filter((entry): entry is string => Boolean(entry && entry !== "*"))
    .map((entry) => normalizeE164(entry))
    .filter((entry): entry is string => Boolean(entry));
}
