/**
 * WhatsApp Web 收件箱监控模块
 *
 * 此模块负责监控 WhatsApp Web 收件箱，处理入站消息，
 * 包括消息过滤、去重、媒体下载、消息处理等功能。
 */
import type { AnyMessageContent, proto, WAMessage } from "@whiskeysockets/baileys";
import { DisconnectReason, isJidGroup } from "@whiskeysockets/baileys";
import { formatLocationText } from "../../channels/location.js";
import { logVerbose, shouldLogVerbose } from "../../globals.js";
import { recordChannelActivity } from "../../infra/channel-activity.js";
import { getChildLogger } from "../../logging/logger.js";
import { createSubsystemLogger } from "../../logging/subsystem.js";
import { saveMediaBuffer } from "../../media/store.js";
import { createInboundDebouncer } from "../../auto-reply/inbound-debounce.js";
import { jidToE164, resolveJidToE164 } from "../../utils.js";
import { createWaSocket, getStatusCode, waitForWaConnection } from "../session.js";
import { checkInboundAccessControl } from "./access-control.js";
import { isRecentInboundMessage } from "./dedupe.js";
import {
  describeReplyContext,
  extractLocationData,
  extractMediaPlaceholder,
  extractMentionedJids,
  extractText,
} from "./extract.js";
import { downloadInboundMedia } from "./media.js";
import { createWebSendApi } from "./send-api.js";
import type { WebInboundMessage, WebListenerCloseReason } from "./types.js";

/**
 * 监控 WhatsApp Web 收件箱，处理入站消息
 *
 * @param options 配置选项
 * @param options.verbose 是否启用详细日志
 * @param options.accountId 账户ID
 * @param options.authDir 认证目录路径
 * @param options.onMessage 消息处理回调函数
 * @param options.mediaMaxMb 媒体文件最大大小（MB）
 * @param options.sendReadReceipts 是否发送已读回执（默认true）
 * @param options.debounceMs 消息去抖动窗口（毫秒）
 * @param options.shouldDebounce 去抖动条件判断函数
 * @returns 监控器实例，包含关闭、发送消息等方法
 */
export async function monitorWebInbox(options: {
  verbose: boolean;
  accountId: string;
  authDir: string;
  onMessage: (msg: WebInboundMessage) => Promise<void>;
  mediaMaxMb?: number;
  /** 发送已读回执（默认true） */
  sendReadReceipts?: boolean;
  /** 消息去抖动窗口（毫秒），用于批量处理来自同一发送者的快速连续消息（0表示禁用） */
  debounceMs?: number;
  /** 可选的去抖动条件判断函数 */
  shouldDebounce?: (msg: WebInboundMessage) => boolean;
}) {
  // 创建日志记录器
  const inboundLogger = getChildLogger({ module: "web-inbound" });
  const inboundConsoleLog = createSubsystemLogger("gateway/channels/whatsapp").child("inbound");

  // 创建并连接 WhatsApp Web 套接字
  const sock = await createWaSocket(false, options.verbose, {
    authDir: options.authDir,
  });
  await waitForWaConnection(sock);
  const connectedAtMs = Date.now();

  // 初始化关闭处理
  let onCloseResolve: ((reason: WebListenerCloseReason) => void) | null = null;
  const onClose = new Promise<WebListenerCloseReason>((resolve) => {
    onCloseResolve = resolve;
  });

  /**
   * 处理监听器关闭
   * @param reason 关闭原因
   */
  const resolveClose = (reason: WebListenerCloseReason) => {
    if (!onCloseResolve) return;
    const resolver = onCloseResolve;
    onCloseResolve = null;
    resolver(reason);
  };

  // 发送"可用"状态
  try {
    await sock.sendPresenceUpdate("available");
    if (shouldLogVerbose()) logVerbose("连接时发送全局'可用'状态");
  } catch (err) {
    logVerbose(`连接时发送'可用'状态失败: ${String(err)}`);
  }

  // 获取自身信息
  const selfJid = sock.user?.id;
  const selfE164 = selfJid ? jidToE164(selfJid) : null;

  // 创建消息去抖动器
  const debouncer = createInboundDebouncer<WebInboundMessage>({
    debounceMs: options.debounceMs ?? 0,
    buildKey: (msg) => {
      // 构建去抖动键，用于识别同一发送者的消息
      const senderKey =
        msg.chatType === "group"
          ? (msg.senderJid ?? msg.senderE164 ?? msg.senderName ?? msg.from)
          : msg.from;
      if (!senderKey) return null;
      const conversationKey = msg.chatType === "group" ? msg.chatId : msg.from;
      return `${msg.accountId}:${conversationKey}:${senderKey}`;
    },
    shouldDebounce: options.shouldDebounce,
    onFlush: async (entries) => {
      // 处理批量消息
      const last = entries.at(-1);
      if (!last) return;
      if (entries.length === 1) {
        // 单个消息直接处理
        await options.onMessage(last);
        return;
      }
      // 合并多个消息
      const mentioned = new Set<string>();
      for (const entry of entries) {
        for (const jid of entry.mentionedJids ?? []) mentioned.add(jid);
      }
      const combinedBody = entries
        .map((entry) => entry.body)
        .filter(Boolean)
        .join("\n");
      const combinedMessage: WebInboundMessage = {
        ...last,
        body: combinedBody,
        mentionedJids: mentioned.size > 0 ? Array.from(mentioned) : undefined,
      };
      await options.onMessage(combinedMessage);
    },
    onError: (err) => {
      inboundLogger.error({ error: String(err) }, "处理入站消息失败");
      inboundConsoleLog.error(`处理入站消息失败: ${String(err)}`);
    },
  });

  // 群组元数据缓存
  const groupMetaCache = new Map<
    string,
    { subject?: string; participants?: string[]; expires: number }
  >();
  const GROUP_META_TTL_MS = 5 * 60 * 1000; // 5分钟缓存
  const lidLookup = sock.signalRepository?.lidMapping;

  /**
   * 解析入站消息的JID
   * @param jid JID或电话号码
   * @returns 解析后的E.164格式电话号码或null
   */
  const resolveInboundJid = async (jid: string | null | undefined): Promise<string | null> =>
    resolveJidToE164(jid, { authDir: options.authDir, lidLookup });

  /**
   * 获取群组元数据
   * @param jid 群组JID
   * @returns 群组元数据，包含群组名称、参与者列表等
   */
  const getGroupMeta = async (jid: string) => {
    // 检查缓存
    const cached = groupMetaCache.get(jid);
    if (cached && cached.expires > Date.now()) return cached;
    try {
      // 获取群组元数据
      const meta = await sock.groupMetadata(jid);
      // 解析参与者信息
      const participants =
        (
          await Promise.all(
            meta.participants?.map(async (p) => {
              const mapped = await resolveInboundJid(p.id);
              return mapped ?? p.id;
            }) ?? [],
          )
        ).filter(Boolean) ?? [];
      const entry = {
        subject: meta.subject,
        participants,
        expires: Date.now() + GROUP_META_TTL_MS,
      };
      groupMetaCache.set(jid, entry);
      return entry;
    } catch (err) {
      logVerbose(`获取群组元数据失败 ${jid}: ${String(err)}`);
      return { expires: Date.now() + GROUP_META_TTL_MS };
    }
  };

  /**
   * 处理消息更新
   * @param upsert 消息更新对象
   */
  const handleMessagesUpsert = async (upsert: { type?: string; messages?: Array<WAMessage> }) => {
    // 只处理通知和追加类型的消息
    if (upsert.type !== "notify" && upsert.type !== "append") return;

    for (const msg of upsert.messages ?? []) {
      // 记录通道活动
      recordChannelActivity({
        channel: "whatsapp",
        accountId: options.accountId,
        direction: "inbound",
      });

      const id = msg.key?.id ?? undefined;
      const remoteJid = msg.key?.remoteJid;
      if (!remoteJid) continue;
      // 跳过状态和广播消息
      if (remoteJid.endsWith("@status") || remoteJid.endsWith("@broadcast")) continue;

      const group = isJidGroup(remoteJid) === true;
      // 消息去重
      if (id) {
        const dedupeKey = `${options.accountId}:${remoteJid}:${id}`;
        if (isRecentInboundMessage(dedupeKey)) continue;
      }

      const participantJid = msg.key?.participant ?? undefined;
      // 解析发件人信息
      const from = group ? remoteJid : await resolveInboundJid(remoteJid);
      if (!from) continue;
      const senderE164 = group
        ? participantJid
          ? await resolveInboundJid(participantJid)
          : null
        : from;

      // 获取群组信息
      let groupSubject: string | undefined;
      let groupParticipants: string[] | undefined;
      if (group) {
        const meta = await getGroupMeta(remoteJid);
        groupSubject = meta.subject;
        groupParticipants = meta.participants;
      }

      // 解析消息时间戳
      const messageTimestampMs = msg.messageTimestamp
        ? Number(msg.messageTimestamp) * 1000
        : undefined;

      // 检查访问控制
      const access = await checkInboundAccessControl({
        accountId: options.accountId,
        from,
        selfE164,
        senderE164,
        group,
        pushName: msg.pushName ?? undefined,
        isFromMe: Boolean(msg.key?.fromMe),
        messageTimestampMs,
        connectedAtMs,
        sock: { sendMessage: (jid, content) => sock.sendMessage(jid, content) },
        remoteJid,
      });
      if (!access.allowed) continue;

      // 发送已读回执
      if (id && !access.isSelfChat && options.sendReadReceipts !== false) {
        const participant = msg.key?.participant;
        try {
          await sock.readMessages([{ remoteJid, id, participant, fromMe: false }]);
          if (shouldLogVerbose()) {
            const suffix = participant ? ` (参与者 ${participant})` : "";
            logVerbose(`标记消息 ${id} 为已读 ${remoteJid}${suffix}`);
          }
        } catch (err) {
          logVerbose(`标记消息 ${id} 为已读失败: ${String(err)}`);
        }
      } else if (id && access.isSelfChat && shouldLogVerbose()) {
        // 自聊模式：永远不要代表所有者自动发送已读回执（蓝勾）
        logVerbose(`自聊模式：跳过消息 ${id} 的已读回执`);
      }

      // 如果是历史/离线追赶消息，标记已读但跳过自动回复
      if (upsert.type === "append") continue;

      // 提取消息内容
      const location = extractLocationData(msg.message ?? undefined);
      const locationText = location ? formatLocationText(location) : undefined;
      let body = extractText(msg.message ?? undefined);
      if (locationText) {
        body = [body, locationText].filter(Boolean).join("\n").trim();
      }
      if (!body) {
        body = extractMediaPlaceholder(msg.message ?? undefined);
        if (!body) continue;
      }
      const replyContext = describeReplyContext(msg.message as proto.IMessage | undefined);

      // 处理媒体文件
      let mediaPath: string | undefined;
      let mediaType: string | undefined;
      try {
        const inboundMedia = await downloadInboundMedia(msg as proto.IWebMessageInfo, sock);
        if (inboundMedia) {
          const maxMb =
            typeof options.mediaMaxMb === "number" && options.mediaMaxMb > 0
              ? options.mediaMaxMb
              : 50;
          const maxBytes = maxMb * 1024 * 1024;
          const saved = await saveMediaBuffer(
            inboundMedia.buffer,
            inboundMedia.mimetype,
            "inbound",
            maxBytes,
          );
          mediaPath = saved.path;
          mediaType = inboundMedia.mimetype;
        }
      } catch (err) {
        logVerbose(`入站媒体下载失败: ${String(err)}`);
      }

      const chatJid = remoteJid;

      // 创建消息操作方法
      const sendComposing = async () => {
        try {
          await sock.sendPresenceUpdate("composing", chatJid);
        } catch (err) {
          logVerbose(`状态更新失败: ${String(err)}`);
        }
      };
      const reply = async (text: string) => {
        await sock.sendMessage(chatJid, { text });
      };
      const sendMedia = async (payload: AnyMessageContent) => {
        await sock.sendMessage(chatJid, payload);
      };
      const timestamp = messageTimestampMs;
      const mentionedJids = extractMentionedJids(msg.message as proto.IMessage | undefined);
      const senderName = msg.pushName ?? undefined;

      // 记录入站消息
      inboundLogger.info(
        { from, to: selfE164 ?? "me", body, mediaPath, mediaType, timestamp },
        "入站消息",
      );

      // 构建入站消息对象
      const inboundMessage: WebInboundMessage = {
        id,
        from,
        conversationId: from,
        to: selfE164 ?? "me",
        accountId: access.resolvedAccountId,
        body,
        pushName: senderName,
        timestamp,
        chatType: group ? "group" : "direct",
        chatId: remoteJid,
        senderJid: participantJid,
        senderE164: senderE164 ?? undefined,
        senderName,
        replyToId: replyContext?.id,
        replyToBody: replyContext?.body,
        replyToSender: replyContext?.sender,
        replyToSenderJid: replyContext?.senderJid,
        replyToSenderE164: replyContext?.senderE164,
        groupSubject,
        groupParticipants,
        mentionedJids: mentionedJids ?? undefined,
        selfJid,
        selfE164,
        location: location ?? undefined,
        sendComposing,
        reply,
        sendMedia,
        mediaPath,
        mediaType,
      };

      // 处理消息
      try {
        const task = Promise.resolve(debouncer.enqueue(inboundMessage));
        void task.catch((err) => {
          inboundLogger.error({ error: String(err) }, "处理入站消息失败");
          inboundConsoleLog.error(`处理入站消息失败: ${String(err)}`);
        });
      } catch (err) {
        inboundLogger.error({ error: String(err) }, "处理入站消息失败");
        inboundConsoleLog.error(`处理入站消息失败: ${String(err)}`);
      }
    }
  };

  // 监听消息更新事件
  sock.ev.on("messages.upsert", handleMessagesUpsert);

  /**
   * 处理连接更新
   * @param update 连接状态更新
   */
  const handleConnectionUpdate = (
    update: Partial<import("@whiskeysockets/baileys").ConnectionState>,
  ) => {
    try {
      if (update.connection === "close") {
        const status = getStatusCode(update.lastDisconnect?.error);
        resolveClose({
          status,
          isLoggedOut: status === DisconnectReason.loggedOut,
          error: update.lastDisconnect?.error,
        });
      }
    } catch (err) {
      inboundLogger.error({ error: String(err) }, "连接更新处理程序错误");
      resolveClose({ status: undefined, isLoggedOut: false, error: err });
    }
  };

  // 监听连接更新事件
  sock.ev.on("connection.update", handleConnectionUpdate);

  // 创建发送API
  const sendApi = createWebSendApi({
    sock: {
      sendMessage: (jid: string, content: AnyMessageContent) => sock.sendMessage(jid, content),
      sendPresenceUpdate: (presence, jid?: string) => sock.sendPresenceUpdate(presence, jid),
    },
    defaultAccountId: options.accountId,
  });

  // 返回监控器实例
  return {
    /**
     * 关闭监控器
     */
    close: async () => {
      try {
        const ev = sock.ev as unknown as {
          off?: (event: string, listener: (...args: unknown[]) => void) => void;
          removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
        };
        const messagesUpsertHandler = handleMessagesUpsert as unknown as (
          ...args: unknown[]
        ) => void;
        const connectionUpdateHandler = handleConnectionUpdate as unknown as (
          ...args: unknown[]
        ) => void;
        if (typeof ev.off === "function") {
          ev.off("messages.upsert", messagesUpsertHandler);
          ev.off("connection.update", connectionUpdateHandler);
        } else if (typeof ev.removeListener === "function") {
          ev.removeListener("messages.upsert", messagesUpsertHandler);
          ev.removeListener("connection.update", connectionUpdateHandler);
        }
        sock.ws?.close();
      } catch (err) {
        logVerbose(`关闭套接字失败: ${String(err)}`);
      }
    },
    /**
     * 关闭事件Promise
     */
    onClose,
    /**
     * 发送关闭信号
     * @param reason 关闭原因
     */
    signalClose: (reason?: WebListenerCloseReason) => {
      resolveClose(reason ?? { status: undefined, isLoggedOut: false, error: "closed" });
    },
    // IPC接口（sendMessage/sendPoll/sendReaction/sendComposingTo）
    ...sendApi,
  } as const;
}
