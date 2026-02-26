/**
 * WhatsApp Web 入站消息模块
 *
 * 此模块是 WhatsApp Web 入站消息处理的主入口，
 * 导出了与入站消息相关的核心功能和类型定义。
 */

/**
 * 重置入站消息去重
 *
 * 用于清除消息去重缓存，通常在需要重新开始消息处理时使用。
 */
export { resetWebInboundDedupe } from "./inbound/dedupe.js";

/**
 * 提取消息数据相关函数
 *
 * - extractLocationData: 从消息中提取位置数据
 * - extractMediaPlaceholder: 从消息中提取媒体占位符
 * - extractText: 从消息中提取文本内容
 */
export { extractLocationData, extractMediaPlaceholder, extractText } from "./inbound/extract.js";

/**
 * 监控 WhatsApp Web 收件箱
 *
 * 主要函数，用于启动 WhatsApp Web 收件箱监控，
 * 接收并处理来自 WhatsApp Web 的入站消息。
 */
export { monitorWebInbox } from "./inbound/monitor.js";

/**
 * 入站消息相关类型定义
 *
 * - WebInboundMessage: 表示从 WhatsApp Web 接收到的消息
 * - WebListenerCloseReason: 表示监听器关闭的原因
 */
export type { WebInboundMessage, WebListenerCloseReason } from "./inbound/types.js";
