import { vi } from "vitest";

import type { MockBaileysSocket } from "../../test/mocks/baileys.js";
import { createMockBaileys } from "../../test/mocks/baileys.js";

/**
 * 使用 globalThis 存储模拟配置，以便在 vi.mock 提升后仍然有效
 */
const CONFIG_KEY = Symbol.for("moltbot:testConfigMock");

/**
 * 默认测试配置
 */
const DEFAULT_CONFIG = {
  channels: {
    whatsapp: {
      // 测试可以覆盖；默认保持开放以避免意外的测试数据
      allowFrom: ["*"],
    },
  },
  messages: {
    messagePrefix: undefined,
    responsePrefix: undefined,
  },
};

// 如果未设置，初始化默认配置
if (!(globalThis as Record<symbol, unknown>)[CONFIG_KEY]) {
  (globalThis as Record<symbol, unknown>)[CONFIG_KEY] = () => DEFAULT_CONFIG;
}

/**
 * 设置 loadConfig 模拟
 * @param fn - 模拟函数或配置对象
 */
export function setLoadConfigMock(fn: unknown) {
  (globalThis as Record<symbol, unknown>)[CONFIG_KEY] = typeof fn === "function" ? fn : () => fn;
}

/**
 * 重置 loadConfig 模拟到默认值
 */
export function resetLoadConfigMock() {
  (globalThis as Record<symbol, unknown>)[CONFIG_KEY] = () => DEFAULT_CONFIG;
}

/**
 * 模拟 config/config.js 模块
 */
vi.mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => {
      const getter = (globalThis as Record<symbol, unknown>)[CONFIG_KEY];
      if (typeof getter === "function") return getter();
      return DEFAULT_CONFIG;
    },
  };
});

/**
 * 模拟 media/store.js 模块
 */
vi.mock("../media/store.js", () => ({
  saveMediaBuffer: vi.fn().mockImplementation(async (_buf: Buffer, contentType?: string) => ({
    id: "mid",
    path: "/tmp/mid",
    size: _buf.length,
    contentType,
  })),
}));

/**
 * 模拟 @whiskeysockets/baileys 模块
 */
vi.mock("@whiskeysockets/baileys", () => {
  const created = createMockBaileys();
  (globalThis as Record<PropertyKey, unknown>)[Symbol.for("moltbot:lastSocket")] =
    created.lastSocket;
  return created.mod;
});

/**
 * 模拟 qrcode-terminal 模块
 */
vi.mock("qrcode-terminal", () => ({
  default: { generate: vi.fn() },
  generate: vi.fn(),
}));

/**
 * Baileys 模块的模拟实例
 */
export const baileys =
  (await import("@whiskeysockets/baileys")) as unknown as typeof import("@whiskeysockets/baileys") & {
    makeWASocket: ReturnType<typeof vi.fn>;
    useMultiFileAuthState: ReturnType<typeof vi.fn>;
    fetchLatestBaileysVersion: ReturnType<typeof vi.fn>;
    makeCacheableSignalKeyStore: ReturnType<typeof vi.fn>;
  };

/**
 * 重置 Baileys 模拟
 */
export function resetBaileysMocks() {
  const recreated = createMockBaileys();
  (globalThis as Record<PropertyKey, unknown>)[Symbol.for("moltbot:lastSocket")] =
    recreated.lastSocket;
  baileys.makeWASocket.mockImplementation(recreated.mod.makeWASocket);
  baileys.useMultiFileAuthState.mockImplementation(recreated.mod.useMultiFileAuthState);
  baileys.fetchLatestBaileysVersion.mockImplementation(recreated.mod.fetchLatestBaileysVersion);
  baileys.makeCacheableSignalKeyStore.mockImplementation(recreated.mod.makeCacheableSignalKeyStore);
}

/**
 * 获取最后创建的 Baileys 套接字
 * @returns MockBaileysSocket 实例
 */
export function getLastSocket(): MockBaileysSocket {
  const getter = (globalThis as Record<PropertyKey, unknown>)[Symbol.for("moltbot:lastSocket")];
  if (typeof getter === "function") return (getter as () => MockBaileysSocket)();
  if (!getter) throw new Error("Baileys mock not initialized");
  throw new Error("Invalid Baileys socket getter");
}
