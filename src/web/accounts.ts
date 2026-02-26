import fs from "node:fs";
import path from "node:path";

import type { MoltbotConfig } from "../config/config.js";
import { resolveOAuthDir } from "../config/paths.js";
import type { DmPolicy, GroupPolicy, WhatsAppAccountConfig } from "../config/types.js";
import { DEFAULT_ACCOUNT_ID } from "../routing/session-key.js";
import { resolveUserPath } from "../utils.js";
import { hasWebCredsSync } from "./auth-store.js";

/**
 * 解析后的 WhatsApp 账户
 */
export type ResolvedWhatsAppAccount = {
  /** 账户 ID */
  accountId: string;
  /** 账户名称 */
  name?: string;
  /** 是否启用 */
  enabled: boolean;
  /** 是否发送已读回执 */
  sendReadReceipts: boolean;
  /** 消息前缀 */
  messagePrefix?: string;
  /** 认证目录 */
  authDir: string;
  /** 是否为旧版认证目录 */
  isLegacyAuthDir: boolean;
  /** 是否为自聊模式 */
  selfChatMode?: boolean;
  /** 允许的发送者列表 */
  allowFrom?: string[];
  /** 群组中允许的发送者列表 */
  groupAllowFrom?: string[];
  /** 群组策略 */
  groupPolicy?: GroupPolicy;
  /** 私聊策略 */
  dmPolicy?: DmPolicy;
  /** 文本分块限制 */
  textChunkLimit?: number;
  /** 分块模式 */
  chunkMode?: "length" | "newline";
  /** 媒体文件最大大小（MB） */
  mediaMaxMb?: number;
  /** 是否阻止流式传输 */
  blockStreaming?: boolean;
  /** 确认反应 */
  ackReaction?: WhatsAppAccountConfig["ackReaction"];
  /** 群组配置 */
  groups?: WhatsAppAccountConfig["groups"];
  /** 去抖动时间（毫秒） */
  debounceMs?: number;
};

/**
 * 列出配置的账户 ID
 * @param cfg - 应用配置
 * @returns 账户 ID 列表
 */
function listConfiguredAccountIds(cfg: MoltbotConfig): string[] {
  const accounts = cfg.channels?.whatsapp?.accounts;
  if (!accounts || typeof accounts !== "object") return [];
  return Object.keys(accounts).filter(Boolean);
}

/**
 * 列出 WhatsApp 认证目录
 * @param cfg - 应用配置
 * @returns 认证目录列表
 */
export function listWhatsAppAuthDirs(cfg: MoltbotConfig): string[] {
  const oauthDir = resolveOAuthDir();
  const whatsappDir = path.join(oauthDir, "whatsapp");
  const authDirs = new Set<string>([oauthDir, path.join(whatsappDir, DEFAULT_ACCOUNT_ID)]);

  const accountIds = listConfiguredAccountIds(cfg);
  for (const accountId of accountIds) {
    authDirs.add(resolveWhatsAppAuthDir({ cfg, accountId }).authDir);
  }

  try {
    const entries = fs.readdirSync(whatsappDir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      authDirs.add(path.join(whatsappDir, entry.name));
    }
  } catch {
    // 忽略目录不存在的情况
  }

  return Array.from(authDirs);
}

/**
 * 检查是否存在任何 WhatsApp 认证
 * @param cfg - 应用配置
 * @returns 是否存在认证
 */
export function hasAnyWhatsAppAuth(cfg: MoltbotConfig): boolean {
  return listWhatsAppAuthDirs(cfg).some((authDir) => hasWebCredsSync(authDir));
}

/**
 * 列出 WhatsApp 账户 ID
 * @param cfg - 应用配置
 * @returns 账户 ID 列表
 */
export function listWhatsAppAccountIds(cfg: MoltbotConfig): string[] {
  const ids = listConfiguredAccountIds(cfg);
  if (ids.length === 0) return [DEFAULT_ACCOUNT_ID];
  return ids.sort((a, b) => a.localeCompare(b));
}

/**
 * 解析默认的 WhatsApp 账户 ID
 * @param cfg - 应用配置
 * @returns 默认账户 ID
 */
export function resolveDefaultWhatsAppAccountId(cfg: MoltbotConfig): string {
  const ids = listWhatsAppAccountIds(cfg);
  if (ids.includes(DEFAULT_ACCOUNT_ID)) return DEFAULT_ACCOUNT_ID;
  return ids[0] ?? DEFAULT_ACCOUNT_ID;
}

/**
 * 解析账户配置
 * @param cfg - 应用配置
 * @param accountId - 账户 ID
 * @returns 账户配置
 */
function resolveAccountConfig(
  cfg: MoltbotConfig,
  accountId: string,
): WhatsAppAccountConfig | undefined {
  const accounts = cfg.channels?.whatsapp?.accounts;
  if (!accounts || typeof accounts !== "object") return undefined;
  const entry = accounts[accountId] as WhatsAppAccountConfig | undefined;
  return entry;
}

/**
 * 解析默认认证目录
 * @param accountId - 账户 ID
 * @returns 认证目录路径
 */
function resolveDefaultAuthDir(accountId: string): string {
  return path.join(resolveOAuthDir(), "whatsapp", accountId);
}

/**
 * 解析旧版认证目录
 * @returns 旧版认证目录路径
 */
function resolveLegacyAuthDir(): string {
  // 旧版 Baileys 凭证存储在与 OAuth 令牌相同的目录中
  return resolveOAuthDir();
}

/**
 * 检查旧版认证是否存在
 * @param authDir - 认证目录
 * @returns 是否存在旧版认证
 */
function legacyAuthExists(authDir: string): boolean {
  try {
    return fs.existsSync(path.join(authDir, "creds.json"));
  } catch {
    return false;
  }
}

/**
 * 解析 WhatsApp 认证目录
 * @param params - 解析参数
 * @param params.cfg - 应用配置
 * @param params.accountId - 账户 ID
 * @returns 认证目录和是否为旧版
 */
export function resolveWhatsAppAuthDir(params: { cfg: MoltbotConfig; accountId: string }): {
  authDir: string;
  isLegacy: boolean;
} {
  const accountId = params.accountId.trim() || DEFAULT_ACCOUNT_ID;
  const account = resolveAccountConfig(params.cfg, accountId);
  const configured = account?.authDir?.trim();
  if (configured) {
    return { authDir: resolveUserPath(configured), isLegacy: false };
  }

  const defaultDir = resolveDefaultAuthDir(accountId);
  if (accountId === DEFAULT_ACCOUNT_ID) {
    const legacyDir = resolveLegacyAuthDir();
    if (legacyAuthExists(legacyDir) && !legacyAuthExists(defaultDir)) {
      return { authDir: legacyDir, isLegacy: true };
    }
  }

  return { authDir: defaultDir, isLegacy: false };
}

/**
 * 解析 WhatsApp 账户
 * @param params - 解析参数
 * @param params.cfg - 应用配置
 * @param params.accountId - 账户 ID
 * @returns 解析后的账户
 */
export function resolveWhatsAppAccount(params: {
  cfg: MoltbotConfig;
  accountId?: string | null;
}): ResolvedWhatsAppAccount {
  const rootCfg = params.cfg.channels?.whatsapp;
  const accountId = params.accountId?.trim() || resolveDefaultWhatsAppAccountId(params.cfg);
  const accountCfg = resolveAccountConfig(params.cfg, accountId);
  const enabled = accountCfg?.enabled !== false;
  const { authDir, isLegacy } = resolveWhatsAppAuthDir({
    cfg: params.cfg,
    accountId,
  });
  return {
    accountId,
    name: accountCfg?.name?.trim() || undefined,
    enabled,
    sendReadReceipts: accountCfg?.sendReadReceipts ?? rootCfg?.sendReadReceipts ?? true,
    messagePrefix:
      accountCfg?.messagePrefix ?? rootCfg?.messagePrefix ?? params.cfg.messages?.messagePrefix,
    authDir,
    isLegacyAuthDir: isLegacy,
    selfChatMode: accountCfg?.selfChatMode ?? rootCfg?.selfChatMode,
    dmPolicy: accountCfg?.dmPolicy ?? rootCfg?.dmPolicy,
    allowFrom: accountCfg?.allowFrom ?? rootCfg?.allowFrom,
    groupAllowFrom: accountCfg?.groupAllowFrom ?? rootCfg?.groupAllowFrom,
    groupPolicy: accountCfg?.groupPolicy ?? rootCfg?.groupPolicy,
    textChunkLimit: accountCfg?.textChunkLimit ?? rootCfg?.textChunkLimit,
    chunkMode: accountCfg?.chunkMode ?? rootCfg?.chunkMode,
    mediaMaxMb: accountCfg?.mediaMaxMb ?? rootCfg?.mediaMaxMb,
    blockStreaming: accountCfg?.blockStreaming ?? rootCfg?.blockStreaming,
    ackReaction: accountCfg?.ackReaction ?? rootCfg?.ackReaction,
    groups: accountCfg?.groups ?? rootCfg?.groups,
    debounceMs: accountCfg?.debounceMs ?? rootCfg?.debounceMs,
  };
}

/**
 * 列出启用的 WhatsApp 账户
 * @param cfg - 应用配置
 * @returns 启用的账户列表
 */
export function listEnabledWhatsAppAccounts(cfg: MoltbotConfig): ResolvedWhatsAppAccount[] {
  return listWhatsAppAccountIds(cfg)
    .map((accountId) => resolveWhatsAppAccount({ cfg, accountId }))
    .filter((account) => account.enabled);
}
