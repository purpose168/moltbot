import fsSync from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";

import { resolveOAuthDir } from "../config/paths.js";
import { info, success } from "../globals.js";
import { getChildLogger } from "../logging.js";
import { DEFAULT_ACCOUNT_ID } from "../routing/session-key.js";
import { defaultRuntime, type RuntimeEnv } from "../runtime.js";
import { formatCliCommand } from "../cli/command-format.js";
import type { WebChannel } from "../utils.js";
import { jidToE164, resolveUserPath } from "../utils.js";

/**
 * 解析默认的 Web 认证目录
 * @returns 认证目录路径
 */
export function resolveDefaultWebAuthDir(): string {
  return path.join(resolveOAuthDir(), "whatsapp", DEFAULT_ACCOUNT_ID);
}

/** 默认的 WhatsApp Web 认证目录 */
export const WA_WEB_AUTH_DIR = resolveDefaultWebAuthDir();

/**
 * 解析 Web 凭证路径
 * @param authDir - 认证目录
 * @returns 凭证文件路径
 */
export function resolveWebCredsPath(authDir: string): string {
  return path.join(authDir, "creds.json");
}

/**
 * 解析 Web 凭证备份路径
 * @param authDir - 认证目录
 * @returns 凭证备份文件路径
 */
export function resolveWebCredsBackupPath(authDir: string): string {
  return path.join(authDir, "creds.json.bak");
}

/**
 * 同步检查是否存在 Web 凭证
 * @param authDir - 认证目录
 * @returns 是否存在有效的凭证
 */
export function hasWebCredsSync(authDir: string): boolean {
  try {
    const stats = fsSync.statSync(resolveWebCredsPath(authDir));
    return stats.isFile() && stats.size > 1;
  } catch {
    return false;
  }
}

/**
 * 读取凭证 JSON 原始内容
 * @param filePath - 文件路径
 * @returns 原始 JSON 字符串或 null
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
 * 尝试从备份恢复凭证
 * @param authDir - 认证目录
 */
export function maybeRestoreCredsFromBackup(authDir: string): void {
  const logger = getChildLogger({ module: "web-session" });
  try {
    const credsPath = resolveWebCredsPath(authDir);
    const backupPath = resolveWebCredsBackupPath(authDir);
    const raw = readCredsJsonRaw(credsPath);
    if (raw) {
      // 验证 creds.json 是否可解析
      JSON.parse(raw);
      return;
    }

    const backupRaw = readCredsJsonRaw(backupPath);
    if (!backupRaw) return;

    // 确保备份可解析后再恢复
    JSON.parse(backupRaw);
    fsSync.copyFileSync(backupPath, credsPath);
    logger.warn({ credsPath }, "restored corrupted WhatsApp creds.json from backup");
  } catch {
    // 忽略错误
  }
}

/**
 * 检查 Web 认证是否存在
 * @param authDir - 认证目录
 * @returns 是否存在有效的认证
 */
export async function webAuthExists(authDir: string = resolveDefaultWebAuthDir()) {
  const resolvedAuthDir = resolveUserPath(authDir);
  maybeRestoreCredsFromBackup(resolvedAuthDir);
  const credsPath = resolveWebCredsPath(resolvedAuthDir);
  try {
    await fs.access(resolvedAuthDir);
  } catch {
    return false;
  }
  try {
    const stats = await fs.stat(credsPath);
    if (!stats.isFile() || stats.size <= 1) return false;
    const raw = await fs.readFile(credsPath, "utf-8");
    JSON.parse(raw);
    return true;
  } catch {
    return false;
  }
}

/**
 * 清除旧版 Baileys 认证状态
 * @param authDir - 认证目录
 */
async function clearLegacyBaileysAuthState(authDir: string) {
  const entries = await fs.readdir(authDir, { withFileTypes: true });
  const shouldDelete = (name: string) => {
    if (name === "oauth.json") return false;
    if (name === "creds.json" || name === "creds.json.bak") return true;
    if (!name.endsWith(".json")) return false;
    return /^(app-state-sync|session|sender-key|pre-key)-/.test(name);
  };
  await Promise.all(
    entries.map(async (entry) => {
      if (!entry.isFile()) return;
      if (!shouldDelete(entry.name)) return;
      await fs.rm(path.join(authDir, entry.name), { force: true });
    }),
  );
}

/**
 * 登出 WhatsApp Web
 * @param params - 登出参数
 * @param params.authDir - 认证目录
 * @param params.isLegacyAuthDir - 是否为旧版认证目录
 * @param params.runtime - 运行时环境
 * @returns 是否成功登出
 */
export async function logoutWeb(params: {
  authDir?: string;
  isLegacyAuthDir?: boolean;
  runtime?: RuntimeEnv;
}) {
  const runtime = params.runtime ?? defaultRuntime;
  const resolvedAuthDir = resolveUserPath(params.authDir ?? resolveDefaultWebAuthDir());
  const exists = await webAuthExists(resolvedAuthDir);
  if (!exists) {
    runtime.log(info("No WhatsApp Web session found; nothing to delete."));
    return false;
  }
  if (params.isLegacyAuthDir) {
    await clearLegacyBaileysAuthState(resolvedAuthDir);
  } else {
    await fs.rm(resolvedAuthDir, { recursive: true, force: true });
  }
  runtime.log(success("Cleared WhatsApp Web credentials."));
  return true;
}

/**
 * 读取 Web 自身 ID
 * @param authDir - 认证目录
 * @returns 自身 ID 信息
 */
export function readWebSelfId(authDir: string = resolveDefaultWebAuthDir()) {
  // 从磁盘读取缓存的 WhatsApp Web 身份（jid + E.164）
  try {
    const credsPath = resolveWebCredsPath(resolveUserPath(authDir));
    if (!fsSync.existsSync(credsPath)) {
      return { e164: null, jid: null } as const;
    }
    const raw = fsSync.readFileSync(credsPath, "utf-8");
    const parsed = JSON.parse(raw) as { me?: { id?: string } } | undefined;
    const jid = parsed?.me?.id ?? null;
    const e164 = jid ? jidToE164(jid, { authDir }) : null;
    return { e164, jid } as const;
  } catch {
    return { e164: null, jid: null } as const;
  }
}

/**
 * 返回缓存的 WhatsApp Web 认证状态的年龄（以毫秒为单位），如果缺失则返回 null。
 * 有助于心跳/可观察性来发现过期的凭证。
 */
export function getWebAuthAgeMs(authDir: string = resolveDefaultWebAuthDir()): number | null {
  try {
    const stats = fsSync.statSync(resolveWebCredsPath(resolveUserPath(authDir)));
    return Date.now() - stats.mtimeMs;
  } catch {
    return null;
  }
}

/**
 * 记录 Web 自身 ID
 * @param authDir - 认证目录
 * @param runtime - 运行时环境
 * @param includeChannelPrefix - 是否包含通道前缀
 */
export function logWebSelfId(
  authDir: string = resolveDefaultWebAuthDir(),
  runtime: RuntimeEnv = defaultRuntime,
  includeChannelPrefix = false,
) {
  // 人性化日志记录当前链接的个人 Web 会话
  const { e164, jid } = readWebSelfId(authDir);
  const details = e164 || jid ? `${e164 ?? "unknown"}${jid ? ` (jid ${jid})` : ""}` : "unknown";
  const prefix = includeChannelPrefix ? "Web Channel: " : "";
  runtime.log(info(`${prefix}${details}`));
}

/**
 * 选择 Web 通道
 * @param pref - 首选通道
 * @param authDir - 认证目录
 * @returns 选择的通道
 */
export async function pickWebChannel(
  pref: WebChannel | "auto",
  authDir: string = resolveDefaultWebAuthDir(),
): Promise<WebChannel> {
  const choice: WebChannel = pref === "auto" ? "web" : pref;
  const hasWeb = await webAuthExists(authDir);
  if (!hasWeb) {
    throw new Error(
      `No WhatsApp Web session found. Run \`${formatCliCommand("moltbot channels login --channel whatsapp --verbose")}\` to link.`,
    );
  }
  return choice;
}
