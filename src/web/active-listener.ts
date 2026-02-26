import { formatCliCommand } from "../cli/command-format.js";
import type { PollInput } from "../polls.js";
import { DEFAULT_ACCOUNT_ID } from "../routing/session-key.js";

/**
 * WhatsApp Web 发送选项
 */
export type ActiveWebSendOptions = {
  /** 是否启用 GIF 播放 */
  gifPlayback?: boolean;
  /** 账户 ID */
  accountId?: string;
};

/**
 * WhatsApp Web 活动监听器
 */
export type ActiveWebListener = {
  /**
   * 发送消息
   * @param to - 目标聊天 ID
   * @param text - 消息文本
   * @param mediaBuffer - 媒体文件缓冲区
   * @param mediaType - 媒体类型
   * @param options - 发送选项
   * @returns 消息 ID
   */
  sendMessage: (
    to: string,
    text: string,
    mediaBuffer?: Buffer,
    mediaType?: string,
    options?: ActiveWebSendOptions,
  ) => Promise<{ messageId: string }>;
  /**
   * 发送投票
   * @param to - 目标聊天 ID
   * @param poll - 投票输入
   * @returns 消息 ID
   */
  sendPoll: (to: string, poll: PollInput) => Promise<{ messageId: string }>;
  /**
   * 发送反应
   * @param chatJid - 聊天 ID
   * @param messageId - 消息 ID
   * @param emoji - 表情符号
   * @param fromMe - 是否来自自己
   * @param participant - 参与者
   */
  sendReaction: (
    chatJid: string,
    messageId: string,
    emoji: string,
    fromMe: boolean,
    participant?: string,
  ) => Promise<void>;
  /**
   * 发送正在输入状态
   * @param to - 目标聊天 ID
   */
  sendComposingTo: (to: string) => Promise<void>;
  /**
   * 关闭监听器
   */
  close?: () => Promise<void>;
};

/** 当前监听器 */
let _currentListener: ActiveWebListener | null = null;

/** 监听器映射 */
const listeners = new Map<string, ActiveWebListener>();

/**
 * 解析 Web 账户 ID
 * @param accountId - 账户 ID
 * @returns 解析后的账户 ID
 */
export function resolveWebAccountId(accountId?: string | null): string {
  return (accountId ?? "").trim() || DEFAULT_ACCOUNT_ID;
}

/**
 * 获取活动的 Web 监听器
 * @param accountId - 账户 ID
 * @returns 账户 ID 和监听器
 */
export function requireActiveWebListener(accountId?: string | null): {
  accountId: string;
  listener: ActiveWebListener;
} {
  const id = resolveWebAccountId(accountId);
  const listener = listeners.get(id) ?? null;
  if (!listener) {
    throw new Error(
      `No active WhatsApp Web listener (account: ${id}). Start the gateway, then link WhatsApp with: ${formatCliCommand(`moltbot channels login --channel whatsapp --account ${id}`)}.`,
    );
  }
  return { accountId: id, listener };
}

/**
 * 设置活动的 Web 监听器
 * @param listener - 监听器
 */
export function setActiveWebListener(listener: ActiveWebListener | null): void;

/**
 * 设置活动的 Web 监听器
 * @param accountId - 账户 ID
 * @param listener - 监听器
 */
export function setActiveWebListener(
  accountId: string | null | undefined,
  listener: ActiveWebListener | null,
): void;

/**
 * 设置活动的 Web 监听器
 * @param accountIdOrListener - 账户 ID 或监听器
 * @param maybeListener - 监听器
 */
export function setActiveWebListener(
  accountIdOrListener: string | ActiveWebListener | null | undefined,
  maybeListener?: ActiveWebListener | null,
): void {
  const { accountId, listener } =
    typeof accountIdOrListener === "string"
      ? { accountId: accountIdOrListener, listener: maybeListener ?? null }
      : {
          accountId: DEFAULT_ACCOUNT_ID,
          listener: accountIdOrListener ?? null,
        };

  const id = resolveWebAccountId(accountId);
  if (!listener) {
    listeners.delete(id);
  } else {
    listeners.set(id, listener);
  }
  if (id === DEFAULT_ACCOUNT_ID) {
    _currentListener = listener;
  }
}

/**
 * 获取活动的 Web 监听器
 * @param accountId - 账户 ID
 * @returns 监听器
 */
export function getActiveWebListener(accountId?: string | null): ActiveWebListener | null {
  const id = resolveWebAccountId(accountId);
  return listeners.get(id) ?? null;
}
