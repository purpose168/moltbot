import { EventEmitter } from "node:events";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { resetLogger, setLoggerOverride } from "../logging.js";

/**
 * 模拟 session.js 模块
 * 用于测试 loginWeb 函数
 */
vi.mock("./session.js", () => {
  const ev = new EventEmitter();
  const sock = {
    ev,
    ws: { close: vi.fn() },
    sendPresenceUpdate: vi.fn(),
    sendMessage: vi.fn(),
  };
  return {
    createWaSocket: vi.fn().mockResolvedValue(sock),
    waitForWaConnection: vi.fn().mockResolvedValue(undefined),
  };
});

import { loginWeb } from "./login.js";
import type { waitForWaConnection } from "./session.js";

const { createWaSocket } = await import("./session.js");

/**
 * Web 登录测试
 */
describe("web login", () => {
  /**
   * 测试前清理所有模拟
   */
  beforeEach(() => {
    vi.clearAllMocks();
  });

  /**
   * 测试后重置日志
   */
  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
  });

  /**
   * 测试 loginWeb 函数是否等待连接并关闭
   */
  it("loginWeb waits for connection and closes", async () => {
    const sock = await createWaSocket();
    const close = vi.spyOn(sock.ws, "close");
    const waiter: typeof waitForWaConnection = vi.fn().mockResolvedValue(undefined);
    await loginWeb(false, waiter);
    await new Promise((resolve) => setTimeout(resolve, 550));
    expect(close).toHaveBeenCalled();
  });
});
