import { DisconnectReason } from "@whiskeysockets/baileys";
import { loadConfig } from "../config/config.js";
import { danger, info, success } from "../globals.js";
import { logInfo } from "../logger.js";
import { defaultRuntime, type RuntimeEnv } from "../runtime.js";
import { formatCliCommand } from "../cli/command-format.js";
import { resolveWhatsAppAccount } from "./accounts.js";
import { createWaSocket, formatError, logoutWeb, waitForWaConnection } from "./session.js";

/**
 * 登录 WhatsApp Web 并保存凭证
 * @param verbose - 是否启用详细日志
 * @param waitForConnection - 等待连接的函数（可选，默认使用内置的 waitForWaConnection）
 * @param runtime - 运行时环境（可选，默认使用 defaultRuntime）
 * @param accountId - 账户 ID（可选，用于多账户场景）
 *
 * @returns Promise<void> - 登录成功后无返回值
 *
 * @description
 * 此函数负责：
 * 1. 加载配置并解析 WhatsApp 账户
 * 2. 创建 WhatsApp Web 套接字连接
 * 3. 等待连接建立
 * 4. 处理常见错误（如登录过期、配对后需要重启等）
 * 5. 登录成功后保存凭证并关闭连接
 */
export async function loginWeb(
  verbose: boolean,
  waitForConnection?: typeof waitForWaConnection,
  runtime: RuntimeEnv = defaultRuntime,
  accountId?: string,
) {
  // 使用传入的等待函数或默认函数
  const wait = waitForConnection ?? waitForWaConnection;
  // 加载全局配置
  const cfg = loadConfig();
  // 解析 WhatsApp 账户配置
  const account = resolveWhatsAppAccount({ cfg, accountId });

  // 创建 WhatsApp Web 套接字连接
  const sock = await createWaSocket(true, verbose, {
    authDir: account.authDir,
  });

  // 记录等待连接的日志
  logInfo("正在等待 WhatsApp 连接...", runtime);

  try {
    // 等待连接建立
    await wait(sock);
    // 连接成功，显示成功消息
    console.log(success("✅ 已链接！凭证已保存，可供未来发送使用。"));
  } catch (err) {
    // 提取错误状态码
    const code =
      (err as { error?: { output?: { statusCode?: number } } })?.error?.output?.statusCode ??
      (err as { output?: { statusCode?: number } })?.output?.statusCode;

    // 处理配对后需要重启的情况（代码 515）
    if (code === 515) {
      console.log(info("WhatsApp 在配对后要求重启（代码 515）；凭证已保存。正在重启连接一次…"));

      try {
        // 关闭当前连接
        sock.ws?.close();
      } catch {
        // 忽略关闭错误
      }

      // 重新创建连接并尝试
      const retry = await createWaSocket(false, verbose, {
        authDir: account.authDir,
      });

      try {
        // 等待重新连接
        await wait(retry);
        console.log(success("✅ 重启后已链接；Web 会话已准备就绪。"));
        return;
      } finally {
        // 延迟关闭重新连接的套接字
        setTimeout(() => retry.ws?.close(), 500);
      }
    }

    // 处理会话已注销的情况
    if (code === DisconnectReason.loggedOut) {
      // 清理缓存的会话
      await logoutWeb({
        authDir: account.authDir,
        isLegacyAuthDir: account.isLegacyAuthDir,
        runtime,
      });

      // 显示错误消息并提示重新登录
      console.error(
        danger(
          `WhatsApp 报告会话已注销。已清除缓存的 Web 会话；请重新运行 ${formatCliCommand("moltbot channels login")} 并重新扫描二维码。`,
        ),
      );
      throw new Error("会话已注销；缓存已清除。请重新运行登录命令。");
    }

    // 处理其他错误
    const formatted = formatError(err);
    console.error(danger(`WhatsApp Web 连接在完全打开前结束。${formatted}`));
    throw new Error(formatted);
  } finally {
    // 让 Baileys 在关闭套接字前刷新所有最终事件
    setTimeout(() => {
      try {
        sock.ws?.close();
      } catch {
        // 忽略关闭错误
      }
    }, 500);
  }
}
