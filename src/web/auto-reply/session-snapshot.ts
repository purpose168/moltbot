import type { loadConfig } from "../../config/config.js";
import {
  evaluateSessionFreshness,
  loadSessionStore,
  resolveChannelResetConfig,
  resolveThreadFlag,
  resolveSessionResetPolicy,
  resolveSessionResetType,
  resolveSessionKey,
  resolveStorePath,
} from "../../config/sessions.js";
import { normalizeMainKey } from "../../routing/session-key.js";

/**
 * 获取会话快照
 *
 * 此函数获取当前会话的详细信息，包括：
 * 1. 会话键
 * 2. 会话条目
 * 3. 会话新鲜度
 * 4. 重置策略
 * 5. 重置类型
 * 6. 每日重置时间
 * 7. 空闲过期时间
 *
 * @param cfg - 应用配置
 * @param from - 发送者信息
 * @param _isHeartbeat - 是否为心跳消息
 * @param ctx - 上下文信息
 * @param ctx.sessionKey - 会话键
 * @param ctx.isGroup - 是否为群组
 * @param ctx.messageThreadId - 消息线程 ID
 * @param ctx.threadLabel - 线程标签
 * @param ctx.threadStarterBody - 线程起始消息内容
 * @param ctx.parentSessionKey - 父会话键
 * @returns 会话快照信息
 */
export function getSessionSnapshot(
  cfg: ReturnType<typeof loadConfig>,
  from: string,
  _isHeartbeat = false,
  ctx?: {
    sessionKey?: string | null;
    isGroup?: boolean;
    messageThreadId?: string | number | null;
    threadLabel?: string | null;
    threadStarterBody?: string | null;
    parentSessionKey?: string | null;
  },
) {
  const sessionCfg = cfg.session;
  const scope = sessionCfg?.scope ?? "per-sender";

  // 解析会话键
  const key =
    ctx?.sessionKey?.trim() ??
    resolveSessionKey(
      scope,
      { From: from, To: "", Body: "" },
      normalizeMainKey(sessionCfg?.mainKey),
    );

  // 加载会话存储
  const store = loadSessionStore(resolveStorePath(sessionCfg?.store));
  const entry = store[key];

  // 解析线程标志
  const isThread = resolveThreadFlag({
    sessionKey: key,
    messageThreadId: ctx?.messageThreadId ?? null,
    threadLabel: ctx?.threadLabel ?? null,
    threadStarterBody: ctx?.threadStarterBody ?? null,
    parentSessionKey: ctx?.parentSessionKey ?? null,
  });

  // 解析重置类型
  const resetType = resolveSessionResetType({ sessionKey: key, isGroup: ctx?.isGroup, isThread });

  // 解析通道重置配置
  const channelReset = resolveChannelResetConfig({
    sessionCfg,
    channel: entry?.lastChannel ?? entry?.channel,
  });

  // 解析重置策略
  const resetPolicy = resolveSessionResetPolicy({
    sessionCfg,
    resetType,
    resetOverride: channelReset,
  });

  // 评估会话新鲜度
  const now = Date.now();
  const freshness = entry
    ? evaluateSessionFreshness({ updatedAt: entry.updatedAt, now, policy: resetPolicy })
    : { fresh: false };

  return {
    key,
    entry,
    fresh: freshness.fresh,
    resetPolicy,
    resetType,
    dailyResetAt: freshness.dailyResetAt,
    idleExpiresAt: freshness.idleExpiresAt,
  };
}
