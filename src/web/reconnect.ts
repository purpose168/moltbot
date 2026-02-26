import { randomUUID } from "node:crypto";

import type { MoltbotConfig } from "../config/config.js";
import type { BackoffPolicy } from "../infra/backoff.js";
import { computeBackoff, sleepWithAbort } from "../infra/backoff.js";

/**
 * 重连策略类型
 *
 * @property initialMs 初始重连延迟（毫秒）
 * @property maxMs 最大重连延迟（毫秒）
 * @property factor 退避因子
 * @property jitter 抖动因子
 * @property maxAttempts 最大重连尝试次数
 */
export type ReconnectPolicy = BackoffPolicy & {
  maxAttempts: number;
};

/**
 * 默认心跳间隔（秒）
 */
export const DEFAULT_HEARTBEAT_SECONDS = 60;

/**
 * 默认重连策略
 */
export const DEFAULT_RECONNECT_POLICY: ReconnectPolicy = {
  initialMs: 2_000,
  maxMs: 30_000,
  factor: 1.8,
  jitter: 0.25,
  maxAttempts: 12,
};

/**
 * 限制值在指定范围内
 *
 * @param val 要限制的值
 * @param min 最小值
 * @param max 最大值
 * @returns 限制后的值
 */
const clamp = (val: number, min: number, max: number) => Math.max(min, Math.min(max, val));

/**
 * 解析心跳间隔（秒）
 *
 * @param cfg 应用配置
 * @param overrideSeconds 覆盖的秒数（可选）
 * @returns 心跳间隔（秒）
 */
export function resolveHeartbeatSeconds(cfg: MoltbotConfig, overrideSeconds?: number): number {
  const candidate = overrideSeconds ?? cfg.web?.heartbeatSeconds;
  if (typeof candidate === "number" && candidate > 0) return candidate;
  return DEFAULT_HEARTBEAT_SECONDS;
}

/**
 * 解析重连策略
 *
 * @param cfg 应用配置
 * @param overrides 覆盖的策略（可选）
 * @returns 解析后的重连策略
 */
export function resolveReconnectPolicy(
  cfg: MoltbotConfig,
  overrides?: Partial<ReconnectPolicy>,
): ReconnectPolicy {
  const reconnectOverrides = cfg.web?.reconnect ?? {};
  const overrideConfig = overrides ?? {};
  const merged = {
    ...DEFAULT_RECONNECT_POLICY,
    ...reconnectOverrides,
    ...overrideConfig,
  } as ReconnectPolicy;

  merged.initialMs = Math.max(250, merged.initialMs);
  merged.maxMs = Math.max(merged.initialMs, merged.maxMs);
  merged.factor = clamp(merged.factor, 1.1, 10);
  merged.jitter = clamp(merged.jitter, 0, 1);
  merged.maxAttempts = Math.max(0, Math.floor(merged.maxAttempts));
  return merged;
}

/**
 * 计算退避时间
 *
 * @param policy 重连策略
 * @param attempt 尝试次数
 * @returns 退避时间（毫秒）
 */
export { computeBackoff, sleepWithAbort };

/**
 * 创建新的连接 ID
 *
 * @returns 新的连接 ID
 */
export function newConnectionId() {
  return randomUUID();
}
