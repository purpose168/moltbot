import {
  DEFAULT_HEARTBEAT_ACK_MAX_CHARS,
  resolveHeartbeatPrompt,
  stripHeartbeatToken,
} from "../../auto-reply/heartbeat.js";
import { HEARTBEAT_TOKEN } from "../../auto-reply/tokens.js";
import { getReplyFromConfig } from "../../auto-reply/reply.js";
import type { ReplyPayload } from "../../auto-reply/types.js";
import { resolveWhatsAppHeartbeatRecipients } from "../../channels/plugins/whatsapp-heartbeat.js";
import { loadConfig } from "../../config/config.js";
import {
  loadSessionStore,
  resolveSessionKey,
  resolveStorePath,
  updateSessionStore,
} from "../../config/sessions.js";
import { emitHeartbeatEvent, resolveIndicatorType } from "../../infra/heartbeat-events.js";
import { resolveHeartbeatVisibility } from "../../infra/heartbeat-visibility.js";
import { getChildLogger } from "../../logging.js";
import { normalizeMainKey } from "../../routing/session-key.js";
import { sendMessageWhatsApp } from "../outbound.js";
import { newConnectionId } from "../reconnect.js";
import { formatError } from "../session.js";
import { whatsappHeartbeatLog } from "./loggers.js";
import { getSessionSnapshot } from "./session-snapshot.js";
import { elide } from "./util.js";

/**
 * 解析心跳回复 payload
 *
 * @param replyResult - 回复结果，可以是单个 payload、payload 数组或 undefined
 * @returns 有效的回复 payload 或 undefined
 */
function resolveHeartbeatReplyPayload(
  replyResult: ReplyPayload | ReplyPayload[] | undefined,
): ReplyPayload | undefined {
  if (!replyResult) return undefined;
  if (!Array.isArray(replyResult)) return replyResult;
  for (let idx = replyResult.length - 1; idx >= 0; idx -= 1) {
    const payload = replyResult[idx];
    if (!payload) continue;
    if (payload.text || payload.mediaUrl || (payload.mediaUrls && payload.mediaUrls.length > 0)) {
      return payload;
    }
  }
  return undefined;
}

/**
 * 运行一次 WhatsApp Web 心跳检测
 *
 * 此函数执行以下操作：
 * 1. 解析心跳配置和可见性设置
 * 2. 处理手动消息覆盖
 * 3. 生成心跳提示并获取回复
 * 4. 处理空回复和心跳令牌
 * 5. 发送心跳消息
 * 6. 记录心跳事件
 *
 * @param opts - 配置选项
 * @param opts.cfg - 应用配置
 * @param opts.to - 目标联系人
 * @param opts.verbose - 是否启用详细日志
 * @param opts.replyResolver - 回复解析器
 * @param opts.sender - 消息发送器
 * @param opts.sessionId - 会话 ID
 * @param opts.overrideBody - 覆盖消息内容
 * @param opts.dryRun - 是否仅模拟运行
 */
export async function runWebHeartbeatOnce(opts: {
  cfg?: ReturnType<typeof loadConfig>;
  to: string;
  verbose?: boolean;
  replyResolver?: typeof getReplyFromConfig;
  sender?: typeof sendMessageWhatsApp;
  sessionId?: string;
  overrideBody?: string;
  dryRun?: boolean;
}) {
  const { cfg: cfgOverride, to, verbose = false, sessionId, overrideBody, dryRun = false } = opts;
  const replyResolver = opts.replyResolver ?? getReplyFromConfig;
  const sender = opts.sender ?? sendMessageWhatsApp;
  const runId = newConnectionId();
  const heartbeatLogger = getChildLogger({
    module: "web-heartbeat",
    runId,
    to,
  });

  const cfg = cfgOverride ?? loadConfig();

  // 解析 WhatsApp 心跳可见性设置
  const visibility = resolveHeartbeatVisibility({ cfg, channel: "whatsapp" });
  const heartbeatOkText = HEARTBEAT_TOKEN;

  // 处理会话配置
  const sessionCfg = cfg.session;
  const sessionScope = sessionCfg?.scope ?? "per-sender";
  const mainKey = normalizeMainKey(sessionCfg?.mainKey);
  const sessionKey = resolveSessionKey(sessionScope, { From: to }, mainKey);

  // 更新会话 ID（如果提供）
  if (sessionId) {
    const storePath = resolveStorePath(cfg.session?.store);
    const store = loadSessionStore(storePath);
    const current = store[sessionKey] ?? {};
    store[sessionKey] = {
      ...current,
      sessionId,
      updatedAt: Date.now(),
    };
    await updateSessionStore(storePath, (nextStore) => {
      const nextCurrent = nextStore[sessionKey] ?? current;
      nextStore[sessionKey] = {
        ...nextCurrent,
        sessionId,
        updatedAt: Date.now(),
      };
    });
  }

  // 获取会话快照
  const sessionSnapshot = getSessionSnapshot(cfg, to, true);

  // 详细日志记录
  if (verbose) {
    heartbeatLogger.info(
      {
        to,
        sessionKey: sessionSnapshot.key,
        sessionId: sessionId ?? sessionSnapshot.entry?.sessionId ?? null,
        sessionFresh: sessionSnapshot.fresh,
        resetMode: sessionSnapshot.resetPolicy.mode,
        resetAtHour: sessionSnapshot.resetPolicy.atHour,
        idleMinutes: sessionSnapshot.resetPolicy.idleMinutes ?? null,
        dailyResetAt: sessionSnapshot.dailyResetAt ?? null,
        idleExpiresAt: sessionSnapshot.idleExpiresAt ?? null,
      },
      "heartbeat session snapshot",
    );
  }

  // 验证覆盖消息
  if (overrideBody && overrideBody.trim().length === 0) {
    throw new Error("Override body must be non-empty when provided.");
  }

  try {
    // 处理手动消息覆盖
    if (overrideBody) {
      if (dryRun) {
        whatsappHeartbeatLog.info(
          `[dry-run] web send -> ${to}: ${elide(overrideBody.trim(), 200)} (manual message)`,
        );
        return;
      }
      const sendResult = await sender(to, overrideBody, { verbose });
      emitHeartbeatEvent({
        status: "sent",
        to,
        preview: overrideBody.slice(0, 160),
        hasMedia: false,
        channel: "whatsapp",
        indicatorType: visibility.useIndicator ? resolveIndicatorType("sent") : undefined,
      });
      heartbeatLogger.info(
        {
          to,
          messageId: sendResult.messageId,
          chars: overrideBody.length,
          reason: "manual-message",
        },
        "manual heartbeat message sent",
      );
      whatsappHeartbeatLog.info(`manual heartbeat sent to ${to} (id ${sendResult.messageId})`);
      return;
    }

    // 检查是否需要跳过心跳
    if (!visibility.showAlerts && !visibility.showOk && !visibility.useIndicator) {
      heartbeatLogger.info({ to, reason: "alerts-disabled" }, "heartbeat skipped");
      emitHeartbeatEvent({
        status: "skipped",
        to,
        reason: "alerts-disabled",
        channel: "whatsapp",
      });
      return;
    }

    // 生成心跳提示并获取回复
    const replyResult = await replyResolver(
      {
        Body: resolveHeartbeatPrompt(cfg.agents?.defaults?.heartbeat?.prompt),
        From: to,
        To: to,
        MessageSid: sessionId ?? sessionSnapshot.entry?.sessionId,
      },
      { isHeartbeat: true },
      cfg,
    );
    const replyPayload = resolveHeartbeatReplyPayload(replyResult);

    // 处理空回复
    if (
      !replyPayload ||
      (!replyPayload.text && !replyPayload.mediaUrl && !replyPayload.mediaUrls?.length)
    ) {
      heartbeatLogger.info(
        {
          to,
          reason: "empty-reply",
          sessionId: sessionSnapshot.entry?.sessionId ?? null,
        },
        "heartbeat skipped",
      );
      let okSent = false;
      if (visibility.showOk) {
        if (dryRun) {
          whatsappHeartbeatLog.info(`[dry-run] heartbeat ok -> ${to}`);
        } else {
          const sendResult = await sender(to, heartbeatOkText, { verbose });
          okSent = true;
          heartbeatLogger.info(
            {
              to,
              messageId: sendResult.messageId,
              chars: heartbeatOkText.length,
              reason: "heartbeat-ok",
            },
            "heartbeat ok sent",
          );
          whatsappHeartbeatLog.info(`heartbeat ok sent to ${to} (id ${sendResult.messageId})`);
        }
      }
      emitHeartbeatEvent({
        status: "ok-empty",
        to,
        channel: "whatsapp",
        silent: !okSent,
        indicatorType: visibility.useIndicator ? resolveIndicatorType("ok-empty") : undefined,
      });
      return;
    }

    // 处理媒体和心跳令牌
    const hasMedia = Boolean(replyPayload.mediaUrl || (replyPayload.mediaUrls?.length ?? 0) > 0);
    const ackMaxChars = Math.max(
      0,
      cfg.agents?.defaults?.heartbeat?.ackMaxChars ?? DEFAULT_HEARTBEAT_ACK_MAX_CHARS,
    );
    const stripped = stripHeartbeatToken(replyPayload.text, {
      mode: "heartbeat",
      maxAckChars: ackMaxChars,
    });

    // 处理心跳令牌（跳过心跳以保持会话空闲过期）
    if (stripped.shouldSkip && !hasMedia) {
      // 不要让心跳保持会话活跃：恢复之前的 updatedAt 以便空闲过期仍然有效
      const storePath = resolveStorePath(cfg.session?.store);
      const store = loadSessionStore(storePath);
      if (sessionSnapshot.entry && store[sessionSnapshot.key]) {
        store[sessionSnapshot.key].updatedAt = sessionSnapshot.entry.updatedAt;
        await updateSessionStore(storePath, (nextStore) => {
          const nextEntry = nextStore[sessionSnapshot.key];
          if (!nextEntry) return;
          nextStore[sessionSnapshot.key] = {
            ...nextEntry,
            updatedAt: sessionSnapshot.entry.updatedAt,
          };
        });
      }

      heartbeatLogger.info(
        { to, reason: "heartbeat-token", rawLength: replyPayload.text?.length },
        "heartbeat skipped",
      );
      let okSent = false;
      if (visibility.showOk) {
        if (dryRun) {
          whatsappHeartbeatLog.info(`[dry-run] heartbeat ok -> ${to}`);
        } else {
          const sendResult = await sender(to, heartbeatOkText, { verbose });
          okSent = true;
          heartbeatLogger.info(
            {
              to,
              messageId: sendResult.messageId,
              chars: heartbeatOkText.length,
              reason: "heartbeat-ok",
            },
            "heartbeat ok sent",
          );
          whatsappHeartbeatLog.info(`heartbeat ok sent to ${to} (id ${sendResult.messageId})`);
        }
      }
      emitHeartbeatEvent({
        status: "ok-token",
        to,
        channel: "whatsapp",
        silent: !okSent,
        indicatorType: visibility.useIndicator ? resolveIndicatorType("ok-token") : undefined,
      });
      return;
    }

    // 处理媒体（只发送文本）
    if (hasMedia) {
      heartbeatLogger.warn({ to }, "heartbeat reply contained media; sending text only");
    }

    const finalText = stripped.text || replyPayload.text || "";

    // 检查 WhatsApp 的警报是否禁用
    if (!visibility.showAlerts) {
      heartbeatLogger.info({ to, reason: "alerts-disabled" }, "heartbeat skipped");
      emitHeartbeatEvent({
        status: "skipped",
        to,
        reason: "alerts-disabled",
        preview: finalText.slice(0, 200),
        channel: "whatsapp",
        hasMedia,
        indicatorType: visibility.useIndicator ? resolveIndicatorType("sent") : undefined,
      });
      return;
    }

    // 处理模拟运行
    if (dryRun) {
      heartbeatLogger.info({ to, reason: "dry-run", chars: finalText.length }, "heartbeat dry-run");
      whatsappHeartbeatLog.info(`[dry-run] heartbeat -> ${to}: ${elide(finalText, 200)}`);
      return;
    }

    // 发送心跳消息
    const sendResult = await sender(to, finalText, { verbose });
    emitHeartbeatEvent({
      status: "sent",
      to,
      preview: finalText.slice(0, 160),
      hasMedia,
      channel: "whatsapp",
      indicatorType: visibility.useIndicator ? resolveIndicatorType("sent") : undefined,
    });
    heartbeatLogger.info(
      {
        to,
        messageId: sendResult.messageId,
        chars: finalText.length,
        preview: elide(finalText, 140),
      },
      "heartbeat sent",
    );
    whatsappHeartbeatLog.info(`heartbeat alert sent to ${to}`);
  } catch (err) {
    // 处理错误
    const reason = formatError(err);
    heartbeatLogger.warn({ to, error: reason }, "heartbeat failed");
    whatsappHeartbeatLog.warn(`heartbeat failed (${reason})`);
    emitHeartbeatEvent({
      status: "failed",
      to,
      reason,
      channel: "whatsapp",
      indicatorType: visibility.useIndicator ? resolveIndicatorType("failed") : undefined,
    });
    throw err;
  }
}

/**
 * 解析心跳接收者
 *
 * @param cfg - 应用配置
 * @param opts - 选项
 * @param opts.to - 特定接收者
 * @param opts.all - 是否包含所有接收者
 * @returns 心跳接收者列表
 */
export function resolveHeartbeatRecipients(
  cfg: ReturnType<typeof loadConfig>,
  opts: { to?: string; all?: boolean } = {},
) {
  return resolveWhatsAppHeartbeatRecipients(cfg, opts);
}
