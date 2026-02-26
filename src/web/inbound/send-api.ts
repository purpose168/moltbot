/**
 * WhatsApp Web 发送 API
 *
 * 此模块创建一个 Web 发送 API，用于通过 WhatsApp Web 发送消息、媒体、投票和反应。
 * 它处理不同类型的媒体文件，并记录通道活动以进行监控和分析。
 */
import type { AnyMessageContent, WAPresence } from "@whiskeysockets/baileys";
import { recordChannelActivity } from "../../infra/channel-activity.js";
import { toWhatsappJid } from "../../utils.js";
import type { ActiveWebSendOptions } from "../active-listener.js";

/**
 * 创建 Web 发送 API
 *
 * @param params - API 参数
 * @param params.sock - WhatsApp Web 套接字实例
 * @param params.sock.sendMessage - 发送消息的方法
 * @param params.sock.sendPresenceUpdate - 发送状态更新的方法
 * @param params.defaultAccountId - 默认账户 ID
 * @returns 发送 API 对象，包含发送消息、投票、反应等方法
 */
export function createWebSendApi(params: {
  sock: {
    sendMessage: (jid: string, content: AnyMessageContent) => Promise<unknown>;
    sendPresenceUpdate: (presence: WAPresence, jid?: string) => Promise<unknown>;
  };
  defaultAccountId: string;
}) {
  return {
    /**
     * 发送消息
     *
     * @param to - 接收者电话号码或群组 ID
     * @param text - 消息文本
     * @param mediaBuffer - 媒体文件缓冲区（可选）
     * @param mediaType - 媒体文件类型（可选）
     * @param sendOptions - 发送选项（可选）
     * @returns 包含消息 ID 的对象
     */
    sendMessage: async (
      to: string,
      text: string,
      mediaBuffer?: Buffer,
      mediaType?: string,
      sendOptions?: ActiveWebSendOptions,
    ): Promise<{ messageId: string }> => {
      // 转换为 WhatsApp JID 格式
      const jid = toWhatsappJid(to);
      let payload: AnyMessageContent;

      // 根据媒体类型构建消息 payload
      if (mediaBuffer && mediaType) {
        if (mediaType.startsWith("image/")) {
          // 发送图片消息
          payload = {
            image: mediaBuffer,
            caption: text || undefined,
            mimetype: mediaType,
          };
        } else if (mediaType.startsWith("audio/")) {
          // 发送语音消息（按语音消息模式发送）
          payload = { audio: mediaBuffer, ptt: true, mimetype: mediaType };
        } else if (mediaType.startsWith("video/")) {
          // 发送视频消息，支持 GIF 播放模式
          const gifPlayback = sendOptions?.gifPlayback;
          payload = {
            video: mediaBuffer,
            caption: text || undefined,
            mimetype: mediaType,
            ...(gifPlayback ? { gifPlayback: true } : {}),
          };
        } else {
          // 发送其他类型的文件
          payload = {
            document: mediaBuffer,
            fileName: "file",
            caption: text || undefined,
            mimetype: mediaType,
          };
        }
      } else {
        // 发送纯文本消息
        payload = { text };
      }

      // 发送消息
      const result = await params.sock.sendMessage(jid, payload);

      // 确定账户 ID 并记录通道活动
      const accountId = sendOptions?.accountId ?? params.defaultAccountId;
      recordChannelActivity({
        channel: "whatsapp",
        accountId,
        direction: "outbound",
      });

      // 提取消息 ID
      const messageId =
        typeof result === "object" && result && "key" in result
          ? String((result as { key?: { id?: string } }).key?.id ?? "unknown")
          : "unknown";

      return { messageId };
    },

    /**
     * 发送投票消息
     *
     * @param to - 接收者电话号码或群组 ID
     * @param poll - 投票配置
     * @param poll.question - 投票问题
     * @param poll.options - 投票选项数组
     * @param poll.maxSelections - 最大可选数量（默认 1）
     * @returns 包含消息 ID 的对象
     */
    sendPoll: async (
      to: string,
      poll: { question: string; options: string[]; maxSelections?: number },
    ): Promise<{ messageId: string }> => {
      // 转换为 WhatsApp JID 格式
      const jid = toWhatsappJid(to);

      // 发送投票消息
      const result = await params.sock.sendMessage(jid, {
        poll: {
          name: poll.question,
          values: poll.options,
          selectableCount: poll.maxSelections ?? 1,
        },
      } as AnyMessageContent);

      // 记录通道活动
      recordChannelActivity({
        channel: "whatsapp",
        accountId: params.defaultAccountId,
        direction: "outbound",
      });

      // 提取消息 ID
      const messageId =
        typeof result === "object" && result && "key" in result
          ? String((result as { key?: { id?: string } }).key?.id ?? "unknown")
          : "unknown";

      return { messageId };
    },

    /**
     * 发送消息反应（表情回复）
     *
     * @param chatJid - 聊天 ID
     * @param messageId - 要回复的消息 ID
     * @param emoji - 反应表情
     * @param fromMe - 是否从当前用户发送
     * @param participant - 参与者（可选）
     */
    sendReaction: async (
      chatJid: string,
      messageId: string,
      emoji: string,
      fromMe: boolean,
      participant?: string,
    ): Promise<void> => {
      // 转换为 WhatsApp JID 格式
      const jid = toWhatsappJid(chatJid);

      // 发送反应
      await params.sock.sendMessage(jid, {
        react: {
          text: emoji,
          key: {
            remoteJid: jid,
            id: messageId,
            fromMe,
            participant: participant ? toWhatsappJid(participant) : undefined,
          },
        },
      } as AnyMessageContent);
    },

    /**
     * 发送"正在输入"状态
     *
     * @param to - 接收者电话号码或群组 ID
     */
    sendComposingTo: async (to: string): Promise<void> => {
      // 转换为 WhatsApp JID 格式
      const jid = toWhatsappJid(to);

      // 发送"正在输入"状态更新
      await params.sock.sendPresenceUpdate("composing", jid);
    },
  } as const;
}
