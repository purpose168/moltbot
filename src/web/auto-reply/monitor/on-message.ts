/**
 * Web 消息处理模块
 *
 * @description
 * 此模块用于创建和管理 WhatsApp Web 入站消息的处理函数，
 * 支持消息路由解析、群组消息处理、消息广播、回声检测等功能，
 * 是 WhatsApp Web 自动回复系统的核心入口点之一。
 */

import type { MsgContext } from "../../../auto-reply/templating.js";
import type { getReplyFromConfig } from "../../../auto-reply/reply.js";
import type { loadConfig } from "../../../config/config.js";
import { logVerbose } from "../../../globals.js";
import { resolveAgentRoute } from "../../../routing/resolve-route.js";
import { buildGroupHistoryKey } from "../../../routing/session-key.js";
import { normalizeE164 } from "../../../utils.js";
import type { MentionConfig } from "../mentions.js";
import type { WebInboundMsg } from "../types.js";
import { maybeBroadcastMessage } from "./broadcast.js";
import type { EchoTracker } from "./echo.js";
import type { GroupHistoryEntry } from "./group-gating.js";
import { applyGroupGating } from "./group-gating.js";
import { updateLastRouteInBackground } from "./last-route.js";
import { resolvePeerId } from "./peer.js";
import { processMessage } from "./process-message.js";

/**
 * 创建 Web 消息处理函数
 *
 * @description
 * 此函数创建一个处理 WhatsApp Web 入站消息的回调函数，
 * 支持以下核心功能：
 * 1. 消息路由解析 - 确定消息应该由哪个代理处理
 * 2. 群组消息处理和权限控制 - 应用群组门控规则
 * 3. 消息广播到多个代理 - 支持群组消息广播
 * 4. 回声检测 - 避免回复自己发送的消息
 * 5. 后台任务管理 - 处理异步操作
 * 6. 群组历史记录管理 - 维护群组消息上下文
 *
 * @param params - 配置参数
 * @param params.cfg - 应用配置对象
 * @param params.verbose - 是否启用详细日志输出
 * @param params.connectionId - 连接唯一标识符
 * @param params.maxMediaBytes - 媒体文件大小限制（字节）
 * @param params.groupHistoryLimit - 群组历史记录消息数量限制
 * @param params.groupHistories - 群组历史记录映射表
 * @param params.groupMemberNames - 群组成员名称映射表
 * @param params.echoTracker - 回声检测跟踪器
 * @param params.backgroundTasks - 后台任务集合
 * @param params.replyResolver - 回复解析器函数
 * @param params.replyLogger - 回复日志记录器
 * @param params.baseMentionConfig - 基础提及配置
 * @param params.account - 账户信息
 * @returns 消息处理回调函数
 */
export function createWebOnMessageHandler(params: {
  cfg: ReturnType<typeof loadConfig>;
  verbose: boolean;
  connectionId: string;
  maxMediaBytes: number;
  groupHistoryLimit: number;
  groupHistories: Map<string, GroupHistoryEntry[]>;
  groupMemberNames: Map<string, Map<string, string>>;
  echoTracker: EchoTracker;
  backgroundTasks: Set<Promise<unknown>>;
  replyResolver: typeof getReplyFromConfig;
  replyLogger: ReturnType<(typeof import("../../../logging.js"))["getChildLogger"]>;
  baseMentionConfig: MentionConfig;
  account: { authDir?: string; accountId?: string };
}) {
  /**
   * 处理特定路由的消息
   *
   * @description
   * 为特定的代理路由处理入站消息，
   * 调用 processMessage 函数进行实际的消息处理，
   * 并传递所有必要的参数和配置。
   *
   * @param msg - 入站消息对象
   * @param route - 解析后的代理路由
   * @param groupHistoryKey - 群组历史记录键
   * @param opts - 可选配置
   * @param opts.groupHistory - 群组历史记录
   * @param opts.suppressGroupHistoryClear - 是否抑制群组历史记录清除
   * @returns 处理结果
   */
  const processForRoute = async (
    msg: WebInboundMsg,
    route: ReturnType<typeof resolveAgentRoute>,
    groupHistoryKey: string,
    opts?: {
      groupHistory?: GroupHistoryEntry[];
      suppressGroupHistoryClear?: boolean;
    },
  ) =>
    processMessage({
      cfg: params.cfg,
      msg,
      route,
      groupHistoryKey,
      groupHistories: params.groupHistories,
      groupMemberNames: params.groupMemberNames,
      connectionId: params.connectionId,
      verbose: params.verbose,
      maxMediaBytes: params.maxMediaBytes,
      replyResolver: params.replyResolver,
      replyLogger: params.replyLogger,
      backgroundTasks: params.backgroundTasks,
      rememberSentText: params.echoTracker.rememberText,
      echoHas: params.echoTracker.has,
      echoForget: params.echoTracker.forget,
      buildCombinedEchoKey: params.echoTracker.buildCombinedKey,
      groupHistory: opts?.groupHistory,
      suppressGroupHistoryClear: opts?.suppressGroupHistoryClear,
    });

  /**
   * 消息处理回调函数
   *
   * @description
   * 实际处理 WhatsApp Web 入站消息的函数，
   * 执行以下步骤：
   * 1. 确定对话 ID
   * 2. 解析对等方 ID
   * 3. 解析代理路由
   * 4. 构建群组历史记录键
   * 5. 处理同手机模式
   * 6. 执行回声检测
   * 7. 处理群组消息和权限控制
   * 8. 处理私聊消息的 peerId 标准化
   * 9. 执行消息广播
   * 10. 处理消息
   *
   * @param msg - 入站消息对象
   */
  return async (msg: WebInboundMsg) => {
    // 确定对话 ID
    const conversationId = msg.conversationId ?? msg.from;

    // 解析对等方 ID（群组 ID 或用户 ID）
    const peerId = resolvePeerId(msg);

    // 解析代理路由
    const route = resolveAgentRoute({
      cfg: params.cfg,
      channel: "whatsapp",
      accountId: msg.accountId,
      peer: {
        kind: msg.chatType === "group" ? "group" : "dm",
        id: peerId,
      },
    });

    // 构建群组历史记录键
    const groupHistoryKey =
      msg.chatType === "group"
        ? buildGroupHistoryKey({
            channel: "whatsapp",
            accountId: route.accountId,
            peerKind: "group",
            peerId,
          })
        : route.sessionKey;

    // 同手机模式日志
    if (msg.from === msg.to) {
      logVerbose(`📱 检测到同手机模式 (from === to: ${msg.from})`);
    }

    // 跳过自己发送的消息（回声检测）
    if (params.echoTracker.has(msg.body)) {
      logVerbose("跳过自动回复: 检测到回声 (消息与最近发送的文本匹配)");
      params.echoTracker.forget(msg.body);
      return;
    }

    // 群组消息处理
    if (msg.chatType === "group") {
      // 构建消息上下文
      const metaCtx: MsgContext = {
        From: msg.from,
        To: msg.to,
        SessionKey: route.sessionKey,
        AccountId: route.accountId,
        ChatType: msg.chatType,
        ConversationLabel: conversationId,
        GroupSubject: msg.groupSubject,
        SenderName: msg.senderName,
        SenderId: msg.senderJid?.trim() || msg.senderE164,
        SenderE164: msg.senderE164,
        Provider: "whatsapp",
        Surface: "whatsapp",
        OriginatingChannel: "whatsapp",
        OriginatingTo: conversationId,
      };

      // 在后台更新最后路由信息
      updateLastRouteInBackground({
        cfg: params.cfg,
        backgroundTasks: params.backgroundTasks,
        storeAgentId: route.agentId,
        sessionKey: route.sessionKey,
        channel: "whatsapp",
        to: conversationId,
        accountId: route.accountId,
        ctx: metaCtx,
        warn: params.replyLogger.warn.bind(params.replyLogger),
      });

      // 应用群组消息权限控制
      const gating = applyGroupGating({
        cfg: params.cfg,
        msg,
        conversationId,
        groupHistoryKey,
        agentId: route.agentId,
        sessionKey: route.sessionKey,
        baseMentionConfig: params.baseMentionConfig,
        authDir: params.account.authDir,
        groupHistories: params.groupHistories,
        groupHistoryLimit: params.groupHistoryLimit,
        groupMemberNames: params.groupMemberNames,
        logVerbose,
        replyLogger: params.replyLogger,
      });

      // 如果不需要处理（例如：未提及机器人），直接返回
      if (!gating.shouldProcess) return;
    } else {
      // 确保私聊的 peerId 稳定并以 E.164 格式存储
      if (!msg.senderE164 && peerId && peerId.startsWith("+")) {
        msg.senderE164 = normalizeE164(peerId) ?? msg.senderE164;
      }
    }

    // 广播群组：当需要回复时，运行多个代理
    // 不会绕过上面的群组提及/激活控制
    if (
      await maybeBroadcastMessage({
        cfg: params.cfg,
        msg,
        peerId,
        route,
        groupHistoryKey,
        groupHistories: params.groupHistories,
        processMessage: processForRoute,
      })
    ) {
      return;
    }

    // 处理消息
    await processForRoute(msg, route, groupHistoryKey);
  };
}
