/**
 * WhatsApp Web 自动回复类型定义
 *
 * 此模块定义了与 WhatsApp Web 自动回复相关的类型，
 * 包括消息类型、通道状态、监控调优选项等。
 */
import type { monitorWebInbox } from "../inbound.js";
import type { ReconnectPolicy } from "../reconnect.js";

/**
 * Web 入站消息类型
 *
 * 从 monitorWebInbox 函数的 onMessage 回调参数中推断出来的类型，
 * 表示从 WhatsApp Web 接收到的消息对象。
 */
export type WebInboundMsg = Parameters<typeof monitorWebInbox>[0]["onMessage"] extends (
  msg: infer M,
) => unknown
  ? M
  : never;

/**
 * Web 通道状态
 *
 * 表示 WhatsApp Web 通道的当前状态，包含连接状态、
 * 错误信息、时间戳等详细信息。
 */
export type WebChannelStatus = {
  /**
   * 是否正在运行
   * 表示监控进程是否正在执行
   */
  running: boolean;
  /**
   * 是否已连接
   * 表示与 WhatsApp Web 的连接状态
   */
  connected: boolean;
  /**
   * 重连尝试次数
   * 表示断开连接后的重连尝试次数
   */
  reconnectAttempts: number;
  /**
   * 最后连接时间戳（可选）
   * 表示最后一次成功连接的时间戳
   */
  lastConnectedAt?: number | null;
  /**
   * 最后断开连接的信息（可选）
   * 包含断开连接的详细信息
   */
  lastDisconnect?: {
    /**
     * 断开时间戳
     * 表示断开连接的时间戳
     */
    at: number;
    /**
     * 状态码（可选）
     * 表示断开连接的 HTTP 状态码或其他错误码
     */
    status?: number;
    /**
     * 错误信息（可选）
     * 包含断开连接时的错误描述
     */
    error?: string;
    /**
     * 是否已登出（可选）
     * 表示是否因为登出操作而断开连接
     */
    loggedOut?: boolean;
  } | null;
  /**
   * 最后消息时间戳（可选）
   * 表示最后一次处理消息的时间戳
   */
  lastMessageAt?: number | null;
  /**
   * 最后事件时间戳（可选）
   * 表示最后一次处理事件的时间戳
   */
  lastEventAt?: number | null;
  /**
   * 最后错误信息（可选）
   * 表示最后一次发生的错误信息
   */
  lastError?: string | null;
};

/**
 * Web 监控调优选项
 *
 * 用于配置 WhatsApp Web 监控的各种参数，
 * 包括重连策略、心跳间隔、状态监控等。
 */
export type WebMonitorTuning = {
  /**
   * 重连策略（可选）
   * 用于配置断开连接后的重连行为
   */
  reconnect?: Partial<ReconnectPolicy>;
  /**
   * 心跳间隔（秒）（可选）
   * 用于配置心跳检测的时间间隔
   */
  heartbeatSeconds?: number;
  /**
   * 睡眠函数（可选）
   * 用于在需要时暂停执行
   * @param ms - 睡眠毫秒数
   * @param signal - 中止信号（可选）
   * @returns Promise<void>
   */
  sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
  /**
   * 状态接收器（可选）
   * 用于接收和处理通道状态更新
   * @param status - Web 通道状态
   */
  statusSink?: (status: WebChannelStatus) => void;
  /**
   * WhatsApp 账户 ID
   * 默认值："default"
   * 用于标识不同的 WhatsApp 账户
   */
  accountId?: string;
  /**
   * 去抖动窗口（毫秒）
   * 用于批量处理来自同一发送者的快速连续消息，
   * 避免对短时间内的重复消息进行重复处理
   */
  debounceMs?: number;
};
