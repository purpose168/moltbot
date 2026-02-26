/**
 * WhatsApp Web 入站消息类型定义
 *
 * 此模块定义了与 WhatsApp Web 入站消息相关的类型，
 * 包括消息结构、监听器关闭原因等。
 */
import type { AnyMessageContent } from "@whiskeysockets/baileys";
import type { NormalizedLocation } from "../../channels/location.js";

/**
 * Web 监听器关闭原因
 *
 * 表示 WhatsApp Web 监听器关闭的原因和相关信息
 */
export type WebListenerCloseReason = {
  /**
   * 状态码（可选）
   * 表示关闭的 HTTP 状态码或其他错误码
   */
  status?: number;
  /**
   * 是否已登出
   * 表示是否因为登出操作而关闭
   */
  isLoggedOut: boolean;
  /**
   * 错误信息（可选）
   * 包含关闭时的错误详情
   */
  error?: unknown;
};

/**
 * Web 入站消息类型
 *
 * 表示从 WhatsApp Web 接收到的消息，包含完整的消息信息和操作方法
 */
export type WebInboundMessage = {
  /**
   * 消息 ID（可选）
   * WhatsApp 内部的消息唯一标识符
   */
  id?: string;
  /**
   * 发件人 ID
   * - 直接聊天：E.164 格式的电话号码
   * - 群组聊天：群组 JID
   */
  from: string;
  /**
   * 会话 ID
   * 与 from 相同，为了代码清晰度而设置的别名
   */
  conversationId: string;
  /**
   * 收件人 ID
   * 消息的接收者 ID，通常是当前用户的 JID
   */
  to: string;
  /**
   * 账户 ID
   * 关联的 WhatsApp 账户标识符
   */
  accountId: string;
  /**
   * 消息正文
   * 消息的文本内容，如果是媒体消息则可能为空
   */
  body: string;
  /**
   * 推送名称（可选）
   * 发件人的显示名称，在 WhatsApp 中设置的昵称
   */
  pushName?: string;
  /**
   * 时间戳（可选）
   * 消息发送的时间戳，Unix 时间戳格式
   */
  timestamp?: number;
  /**
   * 聊天类型
   * - direct: 直接聊天（一对一）
   * - group: 群组聊天
   */
  chatType: "direct" | "group";
  /**
   * 聊天 ID
   * 聊天会话的唯一标识符
   */
  chatId: string;
  /**
   * 发件人 JID（可选）
   * WhatsApp 内部的用户标识符
   */
  senderJid?: string;
  /**
   * 发件人 E.164 格式电话号码（可选）
   * 标准化格式的发件人电话号码
   */
  senderE164?: string;
  /**
   * 发件人名称（可选）
   * 发件人的完整名称
   */
  senderName?: string;
  /**
   * 回复的消息 ID（可选）
   * 如果是回复消息，则包含被回复的消息 ID
   */
  replyToId?: string;
  /**
   * 回复的消息正文（可选）
   * 如果是回复消息，则包含被回复的消息正文
   */
  replyToBody?: string;
  /**
   * 回复的发件人（可选）
   * 如果是回复消息，则包含被回复的发件人
   */
  replyToSender?: string;
  /**
   * 回复的发件人 JID（可选）
   * 如果是回复消息，则包含被回复的发件人 JID
   */
  replyToSenderJid?: string;
  /**
   * 回复的发件人 E.164 格式电话号码（可选）
   * 如果是回复消息，则包含被回复的发件人电话号码
   */
  replyToSenderE164?: string;
  /**
   * 群组主题（可选）
   * 如果是群组消息，则包含群组名称
   */
  groupSubject?: string;
  /**
   * 群组参与者（可选）
   * 如果是群组消息，则包含群组所有参与者的 JID 列表
   */
  groupParticipants?: string[];
  /**
   * 被提及的 JID 列表（可选）
   * 消息中被 @ 提及的用户 JID 列表
   */
  mentionedJids?: string[];
  /**
   * 自身 JID（可选）
   * 当前用户的 JID
   */
  selfJid?: string | null;
  /**
   * 自身 E.164 格式电话号码（可选）
   * 当前用户的电话号码
   */
  selfE164?: string | null;
  /**
   * 位置信息（可选）
   * 如果是位置消息，则包含标准化的位置信息
   */
  location?: NormalizedLocation;
  /**
   * 发送正在输入状态
   *
   * 向对方显示"正在输入"的状态
   * @returns Promise<void>
   */
  sendComposing: () => Promise<void>;
  /**
   * 回复消息
   *
   * 直接回复此消息
   * @param text - 回复的文本内容
   * @returns Promise<void>
   */
  reply: (text: string) => Promise<void>;
  /**
   * 发送媒体
   *
   * 向消息发送者发送媒体内容
   * @param payload - 媒体内容
   * @returns Promise<void>
   */
  sendMedia: (payload: AnyMessageContent) => Promise<void>;
  /**
   * 媒体文件路径（可选）
   * 如果是媒体消息，则包含本地媒体文件路径
   */
  mediaPath?: string;
  /**
   * 媒体类型（可选）
   * 如果是媒体消息，则包含媒体的 MIME 类型
   */
  mediaType?: string;
  /**
   * 是否被提及（可选）
   * 当前用户是否在消息中被 @ 提及
   */
  wasMentioned?: boolean;
};
