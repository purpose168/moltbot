/**
 * Web 入站消息访问控制模块
 *
 * @description
 * 此模块用于对 WhatsApp Web 入站消息进行访问控制，
 * 根据配置的策略和规则，决定是否允许处理特定消息，
 * 支持群组消息和私聊消息的不同访问控制策略。
 */

import { loadConfig } from "../../config/config.js";
import { logVerbose } from "../../globals.js";
import { buildPairingReply } from "../../pairing/pairing-messages.js";
import {
  readChannelAllowFromStore,
  upsertChannelPairingRequest,
} from "../../pairing/pairing-store.js";
import { isSelfChatMode, normalizeE164 } from "../../utils.js";
import { resolveWhatsAppAccount } from "../accounts.js";

/**
 * 入站访问控制结果类型
 *
 * @description
 * 定义了访问控制检查的返回结果，
 * 包含是否允许处理消息、是否应标记为已读、是否为自聊模式等信息。
 */
export type InboundAccessControlResult = {
  /** 是否允许处理此消息 */
  allowed: boolean;
  /** 是否应将消息标记为已读 */
  shouldMarkRead: boolean;
  /** 是否为自聊模式 */
  isSelfChat: boolean;
  /** 解析后的账号 ID */
  resolvedAccountId: string;
};

/**
 * 配对回复历史的宽限期
 * 设置为 30 秒（30_000 毫秒）
 *
 * @description
 * 用于判断消息是否为历史消息，
 * 超过此时间的历史消息将不会触发配对回复。
 */
const PAIRING_REPLY_HISTORY_GRACE_MS = 30_000;

/**
 * 检查入站消息的访问控制
 *
 * @description
 * 根据配置的策略和规则，检查是否允许处理特定的入站消息，
 * 支持群组消息和私聊消息的不同访问控制策略，
 * 实现了配对模式、白名单模式、开放模式和禁用模式等多种访问控制策略。
 *
 * @param params - 访问控制参数
 * @param params.accountId - 账号 ID
 * @param params.from - 发送者 ID
 * @param params.selfE164 - 自身 E164 格式电话号码
 * @param params.senderE164 - 发送者 E164 格式电话号码
 * @param params.group - 是否为群组消息
 * @param params.pushName - 发送者推送名称
 * @param params.isFromMe - 是否为自己发送的消息
 * @param params.messageTimestampMs - 消息时间戳（毫秒）
 * @param params.connectedAtMs - 连接时间戳（毫秒）
 * @param params.pairingGraceMs - 配对宽限期（毫秒）
 * @param params.sock - WhatsApp 套接字实例
 * @param params.remoteJid - 远程 JID
 * @returns 访问控制结果
 */
export async function checkInboundAccessControl(params: {
  accountId: string;
  from: string;
  selfE164: string | null;
  senderE164: string | null;
  group: boolean;
  pushName?: string;
  isFromMe: boolean;
  messageTimestampMs?: number;
  connectedAtMs?: number;
  pairingGraceMs?: number;
  sock: {
    sendMessage: (jid: string, content: { text: string }) => Promise<unknown>;
  };
  remoteJid: string;
}): Promise<InboundAccessControlResult> {
  // 加载配置
  const cfg = loadConfig();

  // 解析 WhatsApp 账号
  const account = resolveWhatsAppAccount({
    cfg,
    accountId: params.accountId,
  });

  // 获取私聊策略，默认为 "pairing"
  const dmPolicy = cfg.channels?.whatsapp?.dmPolicy ?? "pairing";

  // 获取配置的允许列表
  const configuredAllowFrom = account.allowFrom;

  // 从存储中读取允许列表
  const storeAllowFrom = await readChannelAllowFromStore("whatsapp").catch(() => []);

  // 合并配置的允许列表和存储的允许列表，去除重复项
  const combinedAllowFrom = Array.from(
    new Set([...(configuredAllowFrom ?? []), ...storeAllowFrom]),
  );

  // 如果没有配置允许列表且有自身 E164，则默认只允许自己
  const defaultAllowFrom =
    combinedAllowFrom.length === 0 && params.selfE164 ? [params.selfE164] : undefined;

  // 最终使用的允许列表
  const allowFrom = combinedAllowFrom.length > 0 ? combinedAllowFrom : defaultAllowFrom;

  // 群组允许列表
  const groupAllowFrom =
    account.groupAllowFrom ??
    (configuredAllowFrom && configuredAllowFrom.length > 0 ? configuredAllowFrom : undefined);

  // 检查是否为同一手机号
  const isSamePhone = params.from === params.selfE164;

  // 检查是否为自聊模式
  const isSelfChat = isSelfChatMode(params.selfE164, configuredAllowFrom);

  // 配对宽限期
  const pairingGraceMs =
    typeof params.pairingGraceMs === "number" && params.pairingGraceMs > 0
      ? params.pairingGraceMs
      : PAIRING_REPLY_HISTORY_GRACE_MS;

  // 是否抑制配对回复（对于历史消息）
  const suppressPairingReply =
    typeof params.connectedAtMs === "number" &&
    typeof params.messageTimestampMs === "number" &&
    params.messageTimestampMs < params.connectedAtMs - pairingGraceMs;

  // 预处理允许列表（标准化 E164 格式）
  const dmHasWildcard = allowFrom?.includes("*") ?? false;
  const normalizedAllowFrom =
    allowFrom && allowFrom.length > 0
      ? allowFrom.filter((entry) => entry !== "*").map(normalizeE164)
      : [];

  // 预处理群组允许列表（标准化 E164 格式）
  const groupHasWildcard = groupAllowFrom?.includes("*") ?? false;
  const normalizedGroupAllowFrom =
    groupAllowFrom && groupAllowFrom.length > 0
      ? groupAllowFrom.filter((entry) => entry !== "*").map(normalizeE164)
      : [];

  // 群组消息策略过滤：
  // - "open": 群组消息绕过 allowFrom，只应用提及门控
  // - "disabled": 完全阻止所有群组消息
  // - "allowlist": 只允许来自 groupAllowFrom/allowFrom 中发送者的群组消息
  const defaultGroupPolicy = cfg.channels?.defaults?.groupPolicy;
  const groupPolicy = account.groupPolicy ?? defaultGroupPolicy ?? "open";

  // 如果是群组消息且群组策略为禁用
  if (params.group && groupPolicy === "disabled") {
    logVerbose("Blocked group message (groupPolicy: disabled)");
    return {
      allowed: false,
      shouldMarkRead: false,
      isSelfChat,
      resolvedAccountId: account.accountId,
    };
  }

  // 如果是群组消息且群组策略为白名单
  if (params.group && groupPolicy === "allowlist") {
    // 如果没有配置群组允许列表
    if (!groupAllowFrom || groupAllowFrom.length === 0) {
      logVerbose("Blocked group message (groupPolicy: allowlist, no groupAllowFrom)");
      return {
        allowed: false,
        shouldMarkRead: false,
        isSelfChat,
        resolvedAccountId: account.accountId,
      };
    }

    // 检查发送者是否在允许列表中
    const senderAllowed =
      groupHasWildcard ||
      (params.senderE164 != null && normalizedGroupAllowFrom.includes(params.senderE164));

    // 如果发送者不在允许列表中
    if (!senderAllowed) {
      logVerbose(
        `Blocked group message from ${params.senderE164 ?? "unknown sender"} (groupPolicy: allowlist)`,
      );
      return {
        allowed: false,
        shouldMarkRead: false,
        isSelfChat,
        resolvedAccountId: account.accountId,
      };
    }
  }

  // 私聊访问控制（安全默认值）: "pairing" (默认) / "allowlist" / "open" / "disabled"
  if (!params.group) {
    // 跳过来自自己但不是同一手机号的消息
    if (params.isFromMe && !isSamePhone) {
      logVerbose("Skipping outbound DM (fromMe); no pairing reply needed.");
      return {
        allowed: false,
        shouldMarkRead: false,
        isSelfChat,
        resolvedAccountId: account.accountId,
      };
    }

    // 如果私聊策略为禁用
    if (dmPolicy === "disabled") {
      logVerbose("Blocked dm (dmPolicy: disabled)");
      return {
        allowed: false,
        shouldMarkRead: false,
        isSelfChat,
        resolvedAccountId: account.accountId,
      };
    }

    // 如果私聊策略不是开放模式且不是同一手机号
    if (dmPolicy !== "open" && !isSamePhone) {
      const candidate = params.from;

      // 检查发送者是否在允许列表中
      const allowed =
        dmHasWildcard ||
        (normalizedAllowFrom.length > 0 && normalizedAllowFrom.includes(candidate));

      // 如果发送者不在允许列表中
      if (!allowed) {
        // 如果私聊策略为配对模式
        if (dmPolicy === "pairing") {
          // 如果不是历史消息
          if (!suppressPairingReply) {
            // 创建配对请求
            const { code, created } = await upsertChannelPairingRequest({
              channel: "whatsapp",
              id: candidate,
              meta: { name: (params.pushName ?? "").trim() || undefined },
            });

            // 如果成功创建了配对请求
            if (created) {
              logVerbose(
                `whatsapp pairing request sender=${candidate} name=${params.pushName ?? "unknown"}`,
              );

              // 发送配对回复
              try {
                await params.sock.sendMessage(params.remoteJid, {
                  text: buildPairingReply({
                    channel: "whatsapp",
                    idLine: `Your WhatsApp phone number: ${candidate}`,
                    code,
                  }),
                });
              } catch (err) {
                logVerbose(`whatsapp pairing reply failed for ${candidate}: ${String(err)}`);
              }
            }
          } else {
            logVerbose(`Skipping pairing reply for historical DM from ${candidate}.`);
          }
        } else {
          logVerbose(`Blocked unauthorized sender ${candidate} (dmPolicy=${dmPolicy})`);
        }

        return {
          allowed: false,
          shouldMarkRead: false,
          isSelfChat,
          resolvedAccountId: account.accountId,
        };
      }
    }
  }

  // 允许处理消息
  return {
    allowed: true,
    shouldMarkRead: true,
    isSelfChat,
    resolvedAccountId: account.accountId,
  };
}
