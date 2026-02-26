/**
 * WhatsApp Web 自动回复监控模块
 *
 * 此模块负责监控 WhatsApp Web 通道，处理入站消息，
 * 实现自动回复功能，以及处理连接管理、心跳检测和重连策略。
 */
import { DEFAULT_GROUP_HISTORY_LIMIT } from "../../auto-reply/reply/history.js";
import { getReplyFromConfig } from "../../auto-reply/reply.js";
import { hasControlCommand } from "../../auto-reply/command-detection.js";
import { resolveInboundDebounceMs } from "../../auto-reply/inbound-debounce.js";
import { waitForever } from "../../cli/wait.js";
import { loadConfig } from "../../config/config.js";
import { logVerbose } from "../../globals.js";
import { formatDurationMs } from "../../infra/format-duration.js";
import { enqueueSystemEvent } from "../../infra/system-events.js";
import { registerUnhandledRejectionHandler } from "../../infra/unhandled-rejections.js";
import { getChildLogger } from "../../logging.js";
import { resolveAgentRoute } from "../../routing/resolve-route.js";
import { defaultRuntime, type RuntimeEnv } from "../../runtime.js";
import { formatCliCommand } from "../../cli/command-format.js";
import { resolveWhatsAppAccount } from "../accounts.js";
import { setActiveWebListener } from "../active-listener.js";
import { monitorWebInbox } from "../inbound.js";
import {
  computeBackoff,
  newConnectionId,
  resolveHeartbeatSeconds,
  resolveReconnectPolicy,
  sleepWithAbort,
} from "../reconnect.js";
import { formatError, getWebAuthAgeMs, readWebSelfId } from "../session.js";
import { DEFAULT_WEB_MEDIA_BYTES } from "./constants.js";
import { whatsappHeartbeatLog, whatsappLog } from "./loggers.js";
import { buildMentionConfig } from "./mentions.js";
import { createEchoTracker } from "./monitor/echo.js";
import { createWebOnMessageHandler } from "./monitor/on-message.js";
import type { WebChannelStatus, WebInboundMsg, WebMonitorTuning } from "./types.js";
import { isLikelyWhatsAppCryptoError } from "./util.js";

/**
 * 监控 WhatsApp Web 通道，处理消息和自动回复
 *
 * @param verbose 是否启用详细日志
 * @param listenerFactory 监听器工厂函数
 * @param keepAlive 是否保持连接活跃
 * @param replyResolver 回复解析器函数
 * @param runtime 运行时环境
 * @param abortSignal 中止信号
 * @param tuning 监控调优参数
 *
 * @description
 * 此函数会：
 * 1. 初始化监控状态和日志记录器
 * 2. 加载配置和账户信息
 * 3. 创建消息处理处理器
 * 4. 启动收件箱监听器和心跳检测
 * 5. 处理连接断开和重连逻辑
 * 6. 监控配置变更并相应调整参数
 */
export async function monitorWebChannel(
  verbose: boolean,
  listenerFactory: typeof monitorWebInbox | undefined = monitorWebInbox,
  keepAlive = true,
  replyResolver: typeof getReplyFromConfig | undefined = getReplyFromConfig,
  runtime: RuntimeEnv = defaultRuntime,
  abortSignal?: AbortSignal,
  tuning: WebMonitorTuning = {},
) {
  // 生成连接 ID 并初始化日志记录器
  const runId = newConnectionId();
  const replyLogger = getChildLogger({ module: "web-auto-reply", runId });
  const heartbeatLogger = getChildLogger({ module: "web-heartbeat", runId });
  const reconnectLogger = getChildLogger({ module: "web-reconnect", runId });

  // 初始化通道状态
  const status: WebChannelStatus = {
    running: true,
    connected: false,
    reconnectAttempts: 0,
  };

  // 加载配置和账户信息
  const cfg = loadConfig();
  const account = resolveWhatsAppAccount({ cfg });
  const selfId = readWebSelfId(account.authDir);

  // 初始化各种追踪器和缓存
  const echoTracker = createEchoTracker({});
  const mentionConfig = buildMentionConfig(cfg);
  const groupHistories = new Map<string, any[]>();
  const groupMemberNames = new Map<string, Map<string, string>>();
  const backgroundTasks = new Set<Promise<unknown>>();

  // 创建消息处理处理器
  const onMessage = createWebOnMessageHandler({
    cfg,
    verbose,
    connectionId: runId,
    maxMediaBytes: DEFAULT_WEB_MEDIA_BYTES,
    groupHistoryLimit: DEFAULT_GROUP_HISTORY_LIMIT,
    groupHistories,
    groupMemberNames,
    echoTracker,
    backgroundTasks,
    replyResolver: replyResolver!,
    replyLogger,
    baseMentionConfig: mentionConfig,
    account,
  });

  // 解析初始配置参数
  let reconnectPolicy = resolveReconnectPolicy(cfg);
  let heartbeatSeconds = resolveHeartbeatSeconds(cfg);
  let inboundDebounceMs = resolveInboundDebounceMs({ cfg, channel: "whatsapp" });

  // 配置变更处理函数
  const onConfigChange = () => {
    reconnectPolicy = resolveReconnectPolicy(cfg);
    heartbeatSeconds = resolveHeartbeatSeconds(cfg);
    inboundDebounceMs = resolveInboundDebounceMs({ cfg, channel: "whatsapp" });
  };

  // 注册未处理的拒绝处理程序
  const cleanup = registerUnhandledRejectionHandler((reason) => {
    replyLogger.error({ error: String(reason) }, "未处理的拒绝");
    return true;
  });

  try {
    // 主监控循环
    while (!abortSignal?.aborted) {
      const connectionId = newConnectionId();
      status.reconnectAttempts = 0;
      replyLogger.info(`启动 WhatsApp Web 监听器 (连接 ${connectionId})...`);

      let lastInboxStart: number | undefined;
      let lastInboxEnd: number | undefined;

      // 启动收件箱监听器
      const inboxPromise = (async () => {
        lastInboxStart = Date.now();
        try {
          await listenerFactory({
            verbose,
            accountId: account.accountId,
            authDir: account.authDir,
            onMessage: async (msg: WebInboundMsg) => {
              status.lastMessageAt = Date.now();
              await onMessage(msg);
            },
          });
        } catch (err: any) {
          const errStr = String(err);
          replyLogger.warn(`收件箱监听器错误: ${errStr}`);
          if (isLikelyWhatsAppCryptoError(errStr)) {
            replyLogger.warn(`检测到 WhatsApp 加密错误; 将重新连接`);
          }
          throw err;
        } finally {
          lastInboxEnd = Date.now();
        }
      })();

      // 处理收件箱完成
      const untilInboxDone = (async () => {
        try {
          await inboxPromise;
        } catch (err) {
          replyLogger.warn(`收件箱循环退出，错误: ${formatError(err)}`);
        }
      })();

      // 启动心跳检测
      const heartbeatPromise = (async () => {
        while (!abortSignal?.aborted) {
          try {
            await sleepWithAbort(heartbeatSeconds * 1000, abortSignal);
            if (abortSignal?.aborted) break;

            const authAgeMs = getWebAuthAgeMs(account.authDir);
            const selfId = readWebSelfId(account.authDir);

            const who = selfId.e164 ?? selfId.jid ?? "unknown";
            const authAgeStr = formatDurationMs(authAgeMs || 0);
            const heartbeatOk = (authAgeMs || 0) > 0;

            if (heartbeatOk) {
              heartbeatLogger.info(`活跃: ${who} (认证年龄: ${authAgeStr})`);
            } else {
              heartbeatLogger.info(`未找到认证 (${who})`);
            }
          } catch (err) {
            if (abortSignal?.aborted) break;
            heartbeatLogger.warn(`心跳错误: ${formatError(err)}`);
          }
        }
      })();

      // 等待收件箱完成或心跳错误
      await Promise.race([untilInboxDone, heartbeatPromise]);

      // 检查是否被中止
      if (abortSignal?.aborted) {
        replyLogger.info("监控被中止; 退出");
        break;
      }

      // 检查是否需要保持连接
      if (!keepAlive) {
        replyLogger.info("保活已禁用; 退出");
        break;
      }

      // 计算重连退避时间
      const backoff = computeBackoff(reconnectPolicy, status.reconnectAttempts);
      status.reconnectAttempts++;

      // 计算收件箱持续时间
      const inboxDuration =
        lastInboxStart && lastInboxEnd ? lastInboxEnd - lastInboxStart : undefined;

      // 记录重连信息
      if (inboxDuration && inboxDuration < 1000) {
        reconnectLogger.warn(
          `收件箱监听器很快失败 (${inboxDuration}ms); 可能是致命的认证错误. ` +
            `将等待 ${backoff}ms 后重试.`,
        );
      } else {
        reconnectLogger.info(
          `收件箱监听器已断开; 将在 ${backoff}ms 后重连 (尝试 ${status.reconnectAttempts})`,
        );
      }

      // 等待退避时间后重连
      await sleepWithAbort(backoff, abortSignal);
      if (abortSignal?.aborted) break;

      // 检查配置变更
      onConfigChange();
    }
  } finally {
    // 清理资源
    cleanup();
    status.running = false;
    replyLogger.info("WhatsApp Web 监听器已停止");
  }
}

/**
 * 运行 Web 通道监控
 *
 * @param verbose 是否启用详细日志
 * @param runtime 运行时环境
 *
 * @description
 * 启动 WhatsApp Web 通道监控，保持连接活跃
 */
export async function runWebChannel(verbose: boolean, runtime: RuntimeEnv = defaultRuntime) {
  runtime.log(logVerbose("启动 WhatsApp Web 通道..."));
  await monitorWebChannel(verbose, undefined, true, undefined, runtime);
}
