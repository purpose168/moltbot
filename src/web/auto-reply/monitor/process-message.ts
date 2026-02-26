/**
 * Web 自动回复消息处理模块
 *
 * @description
 * 此模块是 WhatsApp Web 自动回复系统的核心处理单元，
 * 负责处理入站消息、构建回复上下文、生成回复内容、
 * 以及发送回复消息的完整流程。
 */

import { resolveIdentityNamePrefix } from "../../../agents/identity.js";
import { resolveChunkMode, resolveTextChunkLimit } from "../../../auto-reply/chunk.js";
import {
  formatInboundEnvelope,
  resolveEnvelopeFormatOptions,
} from "../../../auto-reply/envelope.js";
import {
  buildHistoryContextFromEntries,
  type HistoryEntry,
} from "../../../auto-reply/reply/history.js";
import { dispatchReplyWithBufferedBlockDispatcher } from "../../../auto-reply/reply/provider-dispatcher.js";
import type { getReplyFromConfig } from "../../../auto-reply/reply.js";
import type { ReplyPayload } from "../../../auto-reply/types.js";
import { shouldComputeCommandAuthorized } from "../../../auto-reply/command-detection.js";
import { finalizeInboundContext } from "../../../auto-reply/reply/inbound-context.js";
import { toLocationContext } from "../../../channels/location.js";
import { createReplyPrefixContext } from "../../../channels/reply-prefix.js";
import type { loadConfig } from "../../../config/config.js";
import {
  readSessionUpdatedAt,
  recordSessionMetaFromInbound,
  resolveStorePath,
} from "../../../config/sessions.js";
import { resolveMarkdownTableMode } from "../../../config/markdown-tables.js";
import { logVerbose, shouldLogVerbose } from "../../../globals.js";
import type { getChildLogger } from "../../../logging.js";
import { readChannelAllowFromStore } from "../../../pairing/pairing-store.js";
import type { resolveAgentRoute } from "../../../routing/resolve-route.js";
import { jidToE164, normalizeE164 } from "../../../utils.js";
import { newConnectionId } from "../../reconnect.js";
import { formatError } from "../../session.js";
import { deliverWebReply } from "../deliver-reply.js";
import { whatsappInboundLog, whatsappOutboundLog } from "../loggers.js";
import type { WebInboundMsg } from "../types.js";
import { elide } from "../util.js";
import { maybeSendAckReaction } from "./ack-reaction.js";
import { formatGroupMembers } from "./group-members.js";
import { trackBackgroundTask, updateLastRouteInBackground } from "./last-route.js";
import { buildInboundLine } from "./message-line.js";

/**
 * 群组历史记录条目类型
 *
 * @description
 * 定义了群组消息历史记录的结构，
 * 包含发送者、消息内容、时间戳等信息，
 * 用于构建群组消息的上下文。
 */
export type GroupHistoryEntry = {
  /** 发送者名称或标识符 */
  sender: string;
  /** 消息内容 */
  body: string;
  /** 消息时间戳（毫秒） */
  timestamp?: number;
  /** 消息 ID */
  id?: string;
  /** 发送者 JID */
  senderJid?: string;
};

/**
 * 标准化允许列表为 E164 格式
 *
 * @description
 * 将允许列表中的值转换为标准化的 E164 格式，
 * 过滤掉空值和通配符，确保格式一致性。
 *
 * @param values - 允许列表值数组
 * @returns 标准化后的 E164 格式字符串数组
 */
function normalizeAllowFromE164(values: Array<string | number> | undefined): string[] {
  const list = Array.isArray(values) ? values : [];
  return list
    .map((entry) => String(entry).trim())
    .filter((entry) => entry && entry !== "*")
    .map((entry) => normalizeE164(entry))
    .filter((entry): entry is string => Boolean(entry));
}

/**
 * 解析 WhatsApp 命令授权
 *
 * @description
 * 检查发送者是否有权限执行命令，
 * 根据配置的访问控制策略进行判断，
 * 支持群组和私聊的不同授权逻辑。
 *
 * @param params - 参数对象
 * @param params.cfg - 配置对象
 * @param params.msg - Web 入站消息
 * @returns 是否授权执行命令
 */
async function resolveWhatsAppCommandAuthorized(params: {
  cfg: ReturnType<typeof loadConfig>;
  msg: WebInboundMsg;
}): Promise<boolean> {
  // 检查是否使用访问组
  const useAccessGroups = params.cfg.commands?.useAccessGroups !== false;
  if (!useAccessGroups) return true;

  // 检查是否为群组消息
  const isGroup = params.msg.chatType === "group";

  // 获取发送者 E164 格式电话号码
  const senderE164 = normalizeE164(
    isGroup ? (params.msg.senderE164 ?? "") : (params.msg.senderE164 ?? params.msg.from ?? ""),
  );
  if (!senderE164) return false;

  // 获取配置的允许列表
  const configuredAllowFrom = params.cfg.channels?.whatsapp?.allowFrom ?? [];
  const configuredGroupAllowFrom =
    params.cfg.channels?.whatsapp?.groupAllowFrom ??
    (configuredAllowFrom.length > 0 ? configuredAllowFrom : undefined);

  // 群组消息授权检查
  if (isGroup) {
    if (!configuredGroupAllowFrom || configuredGroupAllowFrom.length === 0) return false;
    if (configuredGroupAllowFrom.some((v) => String(v).trim() === "*")) return true;
    return normalizeAllowFromE164(configuredGroupAllowFrom).includes(senderE164);
  }

  // 私聊消息授权检查
  const storeAllowFrom = await readChannelAllowFromStore("whatsapp").catch(() => []);
  const combinedAllowFrom = Array.from(
    new Set([...(configuredAllowFrom ?? []), ...storeAllowFrom]),
  );
  const allowFrom =
    combinedAllowFrom.length > 0
      ? combinedAllowFrom
      : params.msg.selfE164
        ? [params.msg.selfE164]
        : [];
  if (allowFrom.some((v) => String(v).trim() === "*")) return true;
  return normalizeAllowFromE164(allowFrom).includes(senderE164);
}

/**
 * 处理 WhatsApp Web 入站消息
 *
 * @description
 * 此函数是自动回复系统的核心处理逻辑，
 * 负责：
 * 1. 构建消息上下文
 * 2. 处理群组历史记录
 * 3. 检测回声消息
 * 4. 发送确认反应
 * 5. 记录消息日志
 * 6. 构建回复上下文
 * 7. 生成并发送回复
 * 8. 处理背景任务
 *
 * @param params - 处理参数
 * @returns 是否发送了回复
 */
export async function processMessage(params: {
  cfg: ReturnType<typeof loadConfig>;
  msg: WebInboundMsg;
  route: ReturnType<typeof resolveAgentRoute>;
  groupHistoryKey: string;
  groupHistories: Map<string, GroupHistoryEntry[]>;
  groupMemberNames: Map<string, Map<string, string>>;
  connectionId: string;
  verbose: boolean;
  maxMediaBytes: number;
  replyResolver: typeof getReplyFromConfig;
  replyLogger: ReturnType<typeof getChildLogger>;
  backgroundTasks: Set<Promise<unknown>>;
  rememberSentText: (
    text: string | undefined,
    opts: {
      combinedBody?: string;
      combinedBodySessionKey?: string;
      logVerboseMessage?: boolean;
    },
  ) => void;
  echoHas: (key: string) => boolean;
  echoForget: (key: string) => void;
  buildCombinedEchoKey: (p: { sessionKey: string; combinedBody: string }) => string;
  maxMediaTextChunkLimit?: number;
  groupHistory?: GroupHistoryEntry[];
  suppressGroupHistoryClear?: boolean;
}) {
  // 获取对话 ID
  const conversationId = params.msg.conversationId ?? params.msg.from;

  // 解析存储路径
  const storePath = resolveStorePath(params.cfg.session?.store, {
    agentId: params.route.agentId,
  });

  // 解析信封格式选项
  const envelopeOptions = resolveEnvelopeFormatOptions(params.cfg);

  // 读取会话更新时间
  const previousTimestamp = readSessionUpdatedAt({
    storePath,
    sessionKey: params.route.sessionKey,
  });

  // 构建入站消息行
  let combinedBody = buildInboundLine({
    cfg: params.cfg,
    msg: params.msg,
    agentId: params.route.agentId,
    previousTimestamp,
    envelope: envelopeOptions,
  });

  // 是否清除群组历史记录
  let shouldClearGroupHistory = false;

  // 处理群组消息历史记录
  if (params.msg.chatType === "group") {
    const history = params.groupHistory ?? params.groupHistories.get(params.groupHistoryKey) ?? [];
    if (history.length > 0) {
      // 构建历史记录条目
      const historyEntries: HistoryEntry[] = history.map((m) => ({
        sender: m.sender,
        body: m.body,
        timestamp: m.timestamp,
        messageId: m.id,
      }));

      // 构建历史上下文
      combinedBody = buildHistoryContextFromEntries({
        entries: historyEntries,
        currentMessage: combinedBody,
        excludeLast: false,
        formatEntry: (entry) => {
          const bodyWithId = entry.messageId
            ? `${entry.body}\n[message_id: ${entry.messageId}]`
            : entry.body;
          return formatInboundEnvelope({
            channel: "WhatsApp",
            from: conversationId,
            timestamp: entry.timestamp,
            body: bodyWithId,
            chatType: "group",
            senderLabel: entry.sender,
            envelope: envelopeOptions,
          });
        },
      });
    }
    shouldClearGroupHistory = !(params.suppressGroupHistoryClear ?? false);
  }

  // 回声检测，避免重复回复
  const combinedEchoKey = params.buildCombinedEchoKey({
    sessionKey: params.route.sessionKey,
    combinedBody,
  });
  if (params.echoHas(combinedEchoKey)) {
    logVerbose("Skipping auto-reply: detected echo for combined message");
    params.echoForget(combinedEchoKey);
    return false;
  }

  // 收到消息后立即发送确认反应
  maybeSendAckReaction({
    cfg: params.cfg,
    msg: params.msg,
    agentId: params.route.agentId,
    sessionKey: params.route.sessionKey,
    conversationId,
    verbose: params.verbose,
    accountId: params.route.accountId,
    info: params.replyLogger.info.bind(params.replyLogger),
    warn: params.replyLogger.warn.bind(params.replyLogger),
  });

  // 生成关联 ID
  const correlationId = params.msg.id ?? newConnectionId();

  // 记录入站消息日志
  params.replyLogger.info(
    {
      connectionId: params.connectionId,
      correlationId,
      from: params.msg.chatType === "group" ? conversationId : params.msg.from,
      to: params.msg.to,
      body: elide(combinedBody, 240),
      mediaType: params.msg.mediaType ?? null,
      mediaPath: params.msg.mediaPath ?? null,
    },
    "inbound web message",
  );

  // 记录 WhatsApp 入站消息日志
  const fromDisplay = params.msg.chatType === "group" ? conversationId : params.msg.from;
  const kindLabel = params.msg.mediaType ? `, ${params.msg.mediaType}` : "";
  whatsappInboundLog.info(
    `Inbound message ${fromDisplay} -> ${params.msg.to} (${params.msg.chatType}${kindLabel}, ${combinedBody.length} chars)`,
  );
  if (shouldLogVerbose()) {
    whatsappInboundLog.debug(`Inbound body: ${elide(combinedBody, 400)}`);
  }

  // 解析私聊路由目标
  const dmRouteTarget =
    params.msg.chatType !== "group"
      ? (() => {
          if (params.msg.senderE164) return normalizeE164(params.msg.senderE164);
          // 在直接聊天中，`msg.from` 已经是规范的对话 ID
          if (params.msg.from.includes("@")) return jidToE164(params.msg.from);
          return normalizeE164(params.msg.from);
        })()
      : undefined;

  // 解析配置参数
  const textLimit = params.maxMediaTextChunkLimit ?? resolveTextChunkLimit(params.cfg, "whatsapp");
  const chunkMode = resolveChunkMode(params.cfg, "whatsapp", params.route.accountId);
  const tableMode = resolveMarkdownTableMode({
    cfg: params.cfg,
    channel: "whatsapp",
    accountId: params.route.accountId,
  });

  // 状态变量
  let didLogHeartbeatStrip = false;
  let didSendReply = false;

  // 检查命令授权
  const commandAuthorized = shouldComputeCommandAuthorized(params.msg.body, params.cfg)
    ? await resolveWhatsAppCommandAuthorized({ cfg: params.cfg, msg: params.msg })
    : undefined;

  // 构建回复前缀上下文
  const configuredResponsePrefix = params.cfg.messages?.responsePrefix;
  const prefixContext = createReplyPrefixContext({
    cfg: params.cfg,
    agentId: params.route.agentId,
  });

  // 检查是否为自聊模式
  const isSelfChat =
    params.msg.chatType !== "group" &&
    Boolean(params.msg.selfE164) &&
    normalizeE164(params.msg.from) === normalizeE164(params.msg.selfE164 ?? "");

  // 确定回复前缀
  const responsePrefix =
    prefixContext.responsePrefix ??
    (configuredResponsePrefix === undefined && isSelfChat
      ? (resolveIdentityNamePrefix(params.cfg, params.route.agentId) ?? "[moltbot]")
      : undefined);

  // 构建入站上下文
  const ctxPayload = finalizeInboundContext({
    Body: combinedBody,
    RawBody: params.msg.body,
    CommandBody: params.msg.body,
    From: params.msg.from,
    To: params.msg.to,
    SessionKey: params.route.sessionKey,
    AccountId: params.route.accountId,
    MessageSid: params.msg.id,
    ReplyToId: params.msg.replyToId,
    ReplyToBody: params.msg.replyToBody,
    ReplyToSender: params.msg.replyToSender,
    MediaPath: params.msg.mediaPath,
    MediaUrl: params.msg.mediaUrl,
    MediaType: params.msg.mediaType,
    ChatType: params.msg.chatType,
    ConversationLabel: params.msg.chatType === "group" ? conversationId : params.msg.from,
    GroupSubject: params.msg.groupSubject,
    GroupMembers: formatGroupMembers({
      participants: params.msg.groupParticipants,
      roster: params.groupMemberNames.get(params.groupHistoryKey),
      fallbackE164: params.msg.senderE164,
    }),
    SenderName: params.msg.senderName,
    SenderId: params.msg.senderJid?.trim() || params.msg.senderE164,
    SenderE164: params.msg.senderE164,
    CommandAuthorized: commandAuthorized,
    WasMentioned: params.msg.wasMentioned,
    ...(params.msg.location ? toLocationContext(params.msg.location) : {}),
    Provider: "whatsapp",
    Surface: "whatsapp",
    OriginatingChannel: "whatsapp",
    OriginatingTo: params.msg.from,
  });

  // 更新最后路由信息
  if (dmRouteTarget) {
    updateLastRouteInBackground({
      cfg: params.cfg,
      backgroundTasks: params.backgroundTasks,
      storeAgentId: params.route.agentId,
      sessionKey: params.route.mainSessionKey,
      channel: "whatsapp",
      to: dmRouteTarget,
      accountId: params.route.accountId,
      ctx: ctxPayload,
      warn: params.replyLogger.warn.bind(params.replyLogger),
    });
  }

  // 记录会话元数据
  const metaTask = recordSessionMetaFromInbound({
    storePath,
    sessionKey: params.route.sessionKey,
    ctx: ctxPayload,
  }).catch((err) => {
    params.replyLogger.warn(
      {
        error: formatError(err),
        storePath,
        sessionKey: params.route.sessionKey,
      },
      "failed updating session meta",
    );
  });
  trackBackgroundTask(params.backgroundTasks, metaTask);

  // 分发回复
  const { queuedFinal } = await dispatchReplyWithBufferedBlockDispatcher({
    ctx: ctxPayload,
    cfg: params.cfg,
    replyResolver: params.replyResolver,
    dispatcherOptions: {
      responsePrefix,
      responsePrefixContextProvider: prefixContext.responsePrefixContextProvider,
      onHeartbeatStrip: () => {
        if (!didLogHeartbeatStrip) {
          didLogHeartbeatStrip = true;
          logVerbose("Stripped stray HEARTBEAT_OK token from web reply");
        }
      },
      deliver: async (payload: ReplyPayload, info) => {
        // 发送 Web 回复
        await deliverWebReply({
          replyResult: payload,
          msg: params.msg,
          maxMediaBytes: params.maxMediaBytes,
          textLimit,
          chunkMode,
          replyLogger: params.replyLogger,
          connectionId: params.connectionId,
          // 工具和块更新比较嘈杂，跳过它们的日志行
          skipLog: info.kind !== "final",
          tableMode,
        });

        didSendReply = true;

        // 记录发送的文本
        if (info.kind === "tool") {
          params.rememberSentText(payload.text, {});
          return;
        }
        const shouldLog = info.kind === "final" && payload.text ? true : undefined;
        params.rememberSentText(payload.text, {
          combinedBody,
          combinedBodySessionKey: params.route.sessionKey,
          logVerboseMessage: shouldLog,
        });

        // 记录最终回复日志
        if (info.kind === "final") {
          const fromDisplay =
            params.msg.chatType === "group" ? conversationId : (params.msg.from ?? "unknown");
          const hasMedia = Boolean(payload.mediaUrl || payload.mediaUrls?.length);
          whatsappOutboundLog.info(`Auto-replied to ${fromDisplay}${hasMedia ? " (media)" : ""}`);
          if (shouldLogVerbose()) {
            const preview = payload.text != null ? elide(payload.text, 400) : "<media>";
            whatsappOutboundLog.debug(`Reply body: ${preview}${hasMedia ? " (media)" : ""}`);
          }
        }
      },
      onError: (err, info) => {
        // 记录错误
        const label =
          info.kind === "tool"
            ? "tool update"
            : info.kind === "block"
              ? "block update"
              : "auto-reply";
        whatsappOutboundLog.error(
          `Failed sending web ${label} to ${params.msg.from ?? conversationId}: ${formatError(err)}`,
        );
      },
      onReplyStart: params.msg.sendComposing,
    },
    replyOptions: {
      disableBlockStreaming:
        typeof params.cfg.channels?.whatsapp?.blockStreaming === "boolean"
          ? !params.cfg.channels.whatsapp.blockStreaming
          : undefined,
      onModelSelected: prefixContext.onModelSelected,
    },
  });

  // 处理群组历史记录清除
  if (!queuedFinal) {
    if (shouldClearGroupHistory) {
      params.groupHistories.set(params.groupHistoryKey, []);
    }
    logVerbose("Skipping auto-reply: silent token or no text/media returned from resolver");
    return false;
  }

  // 清除群组历史记录
  if (shouldClearGroupHistory) {
    params.groupHistories.set(params.groupHistoryKey, []);
  }

  return didSendReply;
}
