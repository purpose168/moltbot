/**
 * Web 入站消息去重模块
 *
 * @description
 * 此模块用于对 WhatsApp Web 入站消息进行去重处理，
 * 避免重复处理相同的消息，提高系统效率和可靠性。
 */

import { createDedupeCache } from "../../infra/dedupe.js";

/**
 * 最近 Web 消息的过期时间
 * 设置为 20 分钟（20 * 60_000 毫秒）
 *
 * @description
 * 超过此时间的消息将被视为过期，不再进行去重检查。
 * 这确保了系统不会无限期地存储消息记录，节省内存空间。
 */
const RECENT_WEB_MESSAGE_TTL_MS = 20 * 60_000;

/**
 * 最近 Web 消息的最大数量
 * 设置为 5000 条消息
 *
 * @description
 * 当存储的消息数量达到此上限时，旧消息将被自动清理，
 * 确保缓存大小不会无限增长，保持系统性能稳定。
 */
const RECENT_WEB_MESSAGE_MAX = 5000;

/**
 * 最近入站消息的去重缓存
 *
 * @description
 * 使用 createDedupeCache 创建的去重缓存实例，
 * 用于存储最近处理过的消息标识符，实现消息去重功能。
 */
const recentInboundMessages = createDedupeCache({
  ttlMs: RECENT_WEB_MESSAGE_TTL_MS,
  maxSize: RECENT_WEB_MESSAGE_MAX,
});

/**
 * 重置 Web 入站消息去重缓存
 *
 * @description
 * 清空所有存储的消息标识符，
 * 通常在系统重启或需要重新开始处理消息时使用。
 */
export function resetWebInboundDedupe(): void {
  recentInboundMessages.clear();
}

/**
 * 检查消息是否是最近处理过的
 *
 * @param key - 消息的唯一标识符
 * @returns 如果消息是最近处理过的，则返回 true；否则返回 false
 *
 * @description
 * 用于检查消息是否已经被处理过，避免重复处理相同的消息。
 * 当消息被检查后，会自动添加到缓存中，以便后续的去重检查。
 */
export function isRecentInboundMessage(key: string): boolean {
  return recentInboundMessages.check(key);
}
