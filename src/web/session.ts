import { randomUUID } from "node:crypto";
import fsSync from "node:fs";
import {
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  makeWASocket,
  useMultiFileAuthState,
} from "@whiskeysockets/baileys";
import qrcode from "qrcode-terminal";
import { danger, success } from "../globals.js";
import { getChildLogger, toPinoLikeLogger } from "../logging.js";
import { ensureDir, resolveUserPath } from "../utils.js";
import { VERSION } from "../version.js";
import { formatCliCommand } from "../cli/command-format.js";

import {
  maybeRestoreCredsFromBackup,
  resolveDefaultWebAuthDir,
  resolveWebCredsBackupPath,
  resolveWebCredsPath,
} from "./auth-store.js";

/**
 * 导出认证相关的函数
 * 这些函数来自 auth-store.js 模块，用于处理：
 * - 获取 Web 认证年龄
 * - 登出 Web 会话
 * - 记录 Web 自身 ID
 * - 选择 Web 通道
 * - 读取 Web 自身 ID
 * - Web 认证目录常量
 * - 检查 Web 认证是否存在
 */
export {
  getWebAuthAgeMs,
  logoutWeb,
  logWebSelfId,
  pickWebChannel,
  readWebSelfId,
  WA_WEB_AUTH_DIR,
  webAuthExists,
} from "./auth-store.js";

/**
 * 凭证保存队列
 * 用于确保凭证保存操作的顺序执行，避免并发写入冲突
 */
let credsSaveQueue: Promise<void> = Promise.resolve();

/**
 * 将凭证保存操作加入队列
 * @param authDir - 认证目录路径
 * @param saveCreds - 保存凭证的函数
 * @param logger - 日志记录器
 */
function enqueueSaveCreds(
  authDir: string,
  saveCreds: () => Promise<void> | void,
  logger: ReturnType<typeof getChildLogger>,
): void {
  credsSaveQueue = credsSaveQueue
    .then(() => safeSaveCreds(authDir, saveCreds, logger))
    .catch((err) => {
      logger.warn({ error: String(err) }, "WhatsApp 凭证保存队列错误");
    });
}

/**
 * 读取凭证 JSON 文件的原始内容
 * @param filePath - 文件路径
 * @returns 读取到的内容，如果文件不存在或为空则返回 null
 */
function readCredsJsonRaw(filePath: string): string | null {
  try {
    if (!fsSync.existsSync(filePath)) return null;
    const stats = fsSync.statSync(filePath);
    if (!stats.isFile() || stats.size <= 1) return null;
    return fsSync.readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

/**
 * 安全保存凭证
 * @param authDir - 认证目录路径
 * @param saveCreds - 保存凭证的函数
 * @param logger - 日志记录器
 */
async function safeSaveCreds(
  authDir: string,
  saveCreds: () => Promise<void> | void,
  logger: ReturnType<typeof getChildLogger>,
): Promise<void> {
  try {
    // 尽力备份，以便在突然重启后恢复
    // 重要：不要用损坏/截断的 creds.json 覆盖好的备份
    const credsPath = resolveWebCredsPath(authDir);
    const backupPath = resolveWebCredsBackupPath(authDir);
    const raw = readCredsJsonRaw(credsPath);
    if (raw) {
      try {
        JSON.parse(raw);
        fsSync.copyFileSync(credsPath, backupPath);
      } catch {
        // 保留现有备份
      }
    }
  } catch {
    // 忽略备份失败
  }
  try {
    await Promise.resolve(saveCreds());
  } catch (err) {
    logger.warn({ error: String(err) }, "保存 WhatsApp 凭证失败");
  }
}

/**
 * 创建 Baileys 套接字，使用多文件认证存储作为后端
 * 消费者可以选择在交互式登录流程中打印二维码
 *
 * @param printQr - 是否在终端打印二维码
 * @param verbose - 是否启用详细日志
 * @param opts - 选项配置
 * @param opts.authDir - 认证目录路径（可选）
 * @param opts.onQr - 二维码生成时的回调函数（可选）
 *
 * @returns 创建的 Baileys 套接字实例
 *
 * @description
 * 此函数负责：
 * 1. 初始化日志记录器
 * 2. 解析认证目录路径
 * 3. 确保认证目录存在
 * 4. 尝试从备份恢复凭证
 * 5. 创建多文件认证状态
 * 6. 获取最新的 Baileys 版本
 * 7. 创建 WhatsApp Web 套接字
 * 8. 监听凭证更新和连接状态变化
 * 9. 处理 WebSocket 级别的错误
 */
export async function createWaSocket(
  printQr: boolean,
  verbose: boolean,
  opts: { authDir?: string; onQr?: (qr: string) => void } = {},
) {
  // 初始化基础日志记录器
  const baseLogger = getChildLogger(
    { module: "baileys" },
    {
      level: verbose ? "info" : "silent",
    },
  );
  const logger = toPinoLikeLogger(baseLogger, verbose ? "info" : "silent");

  // 解析认证目录路径
  const authDir = resolveUserPath(opts.authDir ?? resolveDefaultWebAuthDir());
  await ensureDir(authDir);

  // 初始化会话日志记录器
  const sessionLogger = getChildLogger({ module: "web-session" });

  // 尝试从备份恢复凭证
  maybeRestoreCredsFromBackup(authDir);

  // 创建多文件认证状态
  const { state, saveCreds } = await useMultiFileAuthState(authDir);

  // 获取最新的 Baileys 版本
  const { version } = await fetchLatestBaileysVersion();

  // 创建 WhatsApp Web 套接字
  const sock = makeWASocket({
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    version,
    logger,
    printQRInTerminal: false,
    browser: ["moltbot", "cli", VERSION],
    syncFullHistory: false,
    markOnlineOnConnect: false,
  });

  // 监听凭证更新事件，加入保存队列
  sock.ev.on("creds.update", () => enqueueSaveCreds(authDir, saveCreds, sessionLogger));

  // 监听连接状态更新
  sock.ev.on(
    "connection.update",
    (update: Partial<import("@whiskeysockets/baileys").ConnectionState>) => {
      try {
        const { connection, lastDisconnect, qr } = update;

        // 处理二维码生成事件
        if (qr) {
          opts.onQr?.(qr);
          if (printQr) {
            console.log("请在 WhatsApp 中扫描此二维码（链接设备）：");
            qrcode.generate(qr, { small: true });
          }
        }

        // 处理连接关闭事件
        if (connection === "close") {
          const status = getStatusCode(lastDisconnect?.error);
          if (status === DisconnectReason.loggedOut) {
            console.error(
              danger(`WhatsApp 会话已登出。请运行：${formatCliCommand("moltbot channels login")}`),
            );
          }
        }

        // 处理连接打开事件
        if (connection === "open" && verbose) {
          console.log(success("WhatsApp Web 已连接。"));
        }
      } catch (err) {
        sessionLogger.error({ error: String(err) }, "connection.update 处理器错误");
      }
    },
  );

  // 处理 WebSocket 级别的错误，防止未处理的异常导致进程崩溃
  if (sock.ws && typeof (sock.ws as unknown as { on?: unknown }).on === "function") {
    sock.ws.on("error", (err: Error) => {
      sessionLogger.error({ error: String(err) }, "WebSocket 错误");
    });
  }

  return sock;
}

/**
 * 等待 WhatsApp 连接建立
 * @param sock - Baileys 套接字实例
 * @returns Promise<void> - 连接建立后解析
 *
 * @description
 * 此函数创建一个 Promise，监听连接状态更新事件，
 * 当连接状态变为 "open" 时解析，当变为 "close" 时拒绝。
 */
export async function waitForWaConnection(sock: ReturnType<typeof makeWASocket>) {
  return new Promise<void>((resolve, reject) => {
    type OffCapable = {
      off?: (event: string, listener: (...args: unknown[]) => void) => void;
    };
    const evWithOff = sock.ev as unknown as OffCapable;

    const handler = (...args: unknown[]) => {
      const update = (args[0] ?? {}) as Partial<import("@whiskeysockets/baileys").ConnectionState>;
      if (update.connection === "open") {
        evWithOff.off?.("connection.update", handler);
        resolve();
      }
      if (update.connection === "close") {
        evWithOff.off?.("connection.update", handler);
        reject(update.lastDisconnect ?? new Error("连接已关闭"));
      }
    };

    sock.ev.on("connection.update", handler);
  });
}

/**
 * 从错误对象中提取状态码
 * @param err - 错误对象
 * @returns 状态码，如果不存在则返回 undefined
 */
export function getStatusCode(err: unknown) {
  return (
    (err as { output?: { statusCode?: number } })?.output?.statusCode ??
    (err as { status?: number })?.status
  );
}

/**
 * 安全地将值转换为字符串
 * @param value - 要转换的值
 * @param limit - 字符串长度限制，默认为 800
 * @returns 转换后的字符串
 *
 * @description
 * 此函数能够处理：
 * - 大整数（转换为字符串）
 * - 函数（返回 [Function name] 格式）
 * - 循环引用（返回 [Circular]）
 * - 超长字符串（截断并添加省略号）
 */
function safeStringify(value: unknown, limit = 800): string {
  try {
    const seen = new WeakSet<object>();
    const raw = JSON.stringify(
      value,
      (_key, v) => {
        if (typeof v === "bigint") return v.toString();
        if (typeof v === "function") {
          const maybeName = (v as { name?: unknown }).name;
          const name =
            typeof maybeName === "string" && maybeName.length > 0 ? maybeName : "anonymous";
          return `[Function ${name}]`;
        }
        if (typeof v === "object" && v) {
          if (seen.has(v)) return "[Circular]";
          seen.add(v);
        }
        return v;
      },
      2,
    );
    if (!raw) return String(value);
    return raw.length > limit ? `${raw.slice(0, limit)}…` : raw;
  } catch {
    return String(value);
  }
}

/**
 * 提取 Boom 风格错误的详细信息
 * @param err - 错误对象
 * @returns 错误详细信息对象，如果不是 Boom 风格错误则返回 null
 */
function extractBoomDetails(err: unknown): {
  statusCode?: number;
  error?: string;
  message?: string;
} | null {
  if (!err || typeof err !== "object") return null;
  const output = (err as { output?: unknown })?.output as
    | { statusCode?: unknown; payload?: unknown }
    | undefined;
  if (!output || typeof output !== "object") return null;
  const payload = (output as { payload?: unknown }).payload as
    | { error?: unknown; message?: unknown; statusCode?: unknown }
    | undefined;
  const statusCode =
    typeof (output as { statusCode?: unknown }).statusCode === "number"
      ? ((output as { statusCode?: unknown }).statusCode as number)
      : typeof payload?.statusCode === "number"
        ? (payload.statusCode as number)
        : undefined;
  const error = typeof payload?.error === "string" ? payload.error : undefined;
  const message = typeof payload?.message === "string" ? payload.message : undefined;
  if (!statusCode && !error && !message) return null;
  return { statusCode, error, message };
}

/**
 * 格式化错误信息
 * @param err - 错误对象
 * @returns 格式化后的错误字符串
 *
 * @description
 * 此函数能够处理：
 * 1. Error 实例（返回 message 属性）
 * 2. 字符串（直接返回）
 * 3. 非对象或 null/undefined（转换为字符串）
 * 4. Boom 风格错误（提取状态码、错误类型和消息）
 * 5. 其他对象（提取状态码、错误码和消息）
 * 6. 最终如果无法提取有意义的信息，则使用 safeStringify
 */
export function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (!err || typeof err !== "object") return String(err);

  // Baileys 经常将错误包装在 `error` 属性下，使用 Boom 风格的结构
  const boom =
    extractBoomDetails(err) ??
    extractBoomDetails((err as { error?: unknown })?.error) ??
    extractBoomDetails((err as { lastDisconnect?: { error?: unknown } })?.lastDisconnect?.error);

  const status = boom?.statusCode ?? getStatusCode(err);
  const code = (err as { code?: unknown })?.code;
  const codeText = typeof code === "string" || typeof code === "number" ? String(code) : undefined;

  const messageCandidates = [
    boom?.message,
    typeof (err as { message?: unknown })?.message === "string"
      ? ((err as { message?: unknown }).message as string)
      : undefined,
    typeof (err as { error?: { message?: unknown } })?.error?.message === "string"
      ? ((err as { error?: { message?: unknown } }).error?.message as string)
      : undefined,
  ].filter((v): v is string => Boolean(v && v.trim().length > 0));
  const message = messageCandidates[0];

  const pieces: string[] = [];
  if (typeof status === "number") pieces.push(`status=${status}`);
  if (boom?.error) pieces.push(boom.error);
  if (message) pieces.push(message);
  if (codeText) pieces.push(`code=${codeText}`);

  if (pieces.length > 0) return pieces.join(" ");
  return safeStringify(err);
}

/**
 * 生成新的连接 ID
 * @returns 新的连接 ID（UUID 格式）
 */
export function newConnectionId() {
  return randomUUID();
}
