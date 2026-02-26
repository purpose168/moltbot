import fs from "node:fs/promises";
import path from "node:path";

import { DEFAULT_BOOTSTRAP_FILENAME } from "../agents/workspace.js";
import {
  DEFAULT_GATEWAY_DAEMON_RUNTIME,
  GATEWAY_DAEMON_RUNTIME_OPTIONS,
  type GatewayDaemonRuntime,
} from "../commands/daemon-runtime.js";
import { healthCommand } from "../commands/health.js";
import { formatHealthCheckFailure } from "../commands/health-format.js";
import {
  detectBrowserOpenSupport,
  formatControlUiSshHint,
  openUrl,
  openUrlInBackground,
  probeGatewayReachable,
  waitForGatewayReachable,
  resolveControlUiLinks,
} from "../commands/onboard-helpers.js";
import { formatCliCommand } from "../cli/command-format.js";
import type { OnboardOptions } from "../commands/onboard-types.js";
import type { MoltbotConfig } from "../config/config.js";
import { resolveGatewayService } from "../daemon/service.js";
import { isSystemdUserServiceAvailable } from "../daemon/systemd.js";
import { ensureControlUiAssetsBuilt } from "../infra/control-ui-assets.js";
import type { RuntimeEnv } from "../runtime.js";
import { runTui } from "../tui/tui.js";
import { resolveUserPath } from "../utils.js";
import {
  buildGatewayInstallPlan,
  gatewayInstallErrorHint,
} from "../commands/daemon-install-helpers.js";
import type { GatewayWizardSettings, WizardFlow } from "./onboarding.types.js";
import type { WizardPrompter } from "./prompts.js";

/**
 * 完成入职向导选项类型
 */
type FinalizeOnboardingOptions = {
  /** 向导流程 */
  flow: WizardFlow;
  /** 入职选项 */
  opts: OnboardOptions;
  /** 基础配置 */
  baseConfig: MoltbotConfig;
  /** 下一步配置 */
  nextConfig: MoltbotConfig;
  /** 工作区目录 */
  workspaceDir: string;
  /** 网关设置 */
  settings: GatewayWizardSettings;
  /** 提示器 */
  prompter: WizardPrompter;
  /** 运行时环境 */
  runtime: RuntimeEnv;
};

/**
 * 完成入职向导
 */
export async function finalizeOnboardingWizard(options: FinalizeOnboardingOptions) {
  const { flow, opts, baseConfig, nextConfig, settings, prompter, runtime } = options;

  /**
   * 带向导进度的异步函数
   */
  const withWizardProgress = async <T>(
    label: string,
    options: { doneMessage?: string },
    work: (progress: { update: (message: string) => void }) => Promise<T>,
  ): Promise<T> => {
    const progress = prompter.progress(label);
    try {
      return await work(progress);
    } finally {
      progress.stop(options.doneMessage);
    }
  };

  const systemdAvailable =
    process.platform === "linux" ? await isSystemdUserServiceAvailable() : true;
  if (process.platform === "linux" && !systemdAvailable) {
    await prompter.note("Systemd 用户服务不可用。跳过延迟检查和服务安装。", "Systemd");
  }

  if (process.platform === "linux" && systemdAvailable) {
    const { ensureSystemdUserLingerInteractive } = await import("../commands/systemd-linger.js");
    await ensureSystemdUserLingerInteractive({
      runtime,
      prompter: {
        confirm: prompter.confirm,
        note: prompter.note,
      },
      reason:
        "Linux 安装默认使用 systemd 用户服务。没有延迟，systemd 会在登出/空闲时停止用户会话并终止网关。",
      requireConfirm: false,
    });
  }

  const explicitInstallDaemon =
    typeof opts.installDaemon === "boolean" ? opts.installDaemon : undefined;
  let installDaemon: boolean;
  if (explicitInstallDaemon !== undefined) {
    installDaemon = explicitInstallDaemon;
  } else if (process.platform === "linux" && !systemdAvailable) {
    installDaemon = false;
  } else if (flow === "quickstart") {
    installDaemon = true;
  } else {
    installDaemon = await prompter.confirm({
      message: "安装网关服务（推荐）",
      initialValue: true,
    });
  }

  if (process.platform === "linux" && !systemdAvailable && installDaemon) {
    await prompter.note(
      "Systemd 用户服务不可用；跳过服务安装。使用容器管理器或 `docker compose up -d`。",
      "网关服务",
    );
    installDaemon = false;
  }

  if (installDaemon) {
    const daemonRuntime =
      flow === "quickstart"
        ? (DEFAULT_GATEWAY_DAEMON_RUNTIME as GatewayDaemonRuntime)
        : ((await prompter.select({
            message: "网关服务运行时",
            options: GATEWAY_DAEMON_RUNTIME_OPTIONS,
            initialValue: opts.daemonRuntime ?? DEFAULT_GATEWAY_DAEMON_RUNTIME,
          })) as GatewayDaemonRuntime);
    if (flow === "quickstart") {
      await prompter.note("快速启动使用 Node 作为网关服务（稳定 + 支持）。", "网关服务运行时");
    }
    const service = resolveGatewayService();
    const loaded = await service.isLoaded({ env: process.env });
    if (loaded) {
      const action = (await prompter.select({
        message: "网关服务已安装",
        options: [
          { value: "restart", label: "重启" },
          { value: "reinstall", label: "重新安装" },
          { value: "skip", label: "跳过" },
        ],
      })) as "restart" | "reinstall" | "skip";
      if (action === "restart") {
        await withWizardProgress(
          "网关服务",
          { doneMessage: "网关服务已重启。" },
          async (progress) => {
            progress.update("重启网关服务中…");
            await service.restart({
              env: process.env,
              stdout: process.stdout,
            });
          },
        );
      } else if (action === "reinstall") {
        await withWizardProgress(
          "网关服务",
          { doneMessage: "网关服务已卸载。" },
          async (progress) => {
            progress.update("卸载网关服务中…");
            await service.uninstall({ env: process.env, stdout: process.stdout });
          },
        );
      }
    }

    if (!loaded || (loaded && (await service.isLoaded({ env: process.env })) === false)) {
      const progress = prompter.progress("网关服务");
      let installError: string | null = null;
      try {
        progress.update("准备网关服务中…");
        const { programArguments, workingDirectory, environment } = await buildGatewayInstallPlan({
          env: process.env,
          port: settings.port,
          token: settings.gatewayToken,
          runtime: daemonRuntime,
          warn: (message, title) => prompter.note(message, title),
          config: nextConfig,
        });

        progress.update("安装网关服务中…");
        await service.install({
          env: process.env,
          stdout: process.stdout,
          programArguments,
          workingDirectory,
          environment,
        });
      } catch (err) {
        installError = err instanceof Error ? err.message : String(err);
      } finally {
        progress.stop(installError ? "网关服务安装失败。" : "网关服务已安装。");
      }
      if (installError) {
        await prompter.note(`网关服务安装失败：${installError}`, "网关");
        await prompter.note(gatewayInstallErrorHint(), "网关");
      }
    }
  }

  if (!opts.skipHealth) {
    const probeLinks = resolveControlUiLinks({
      bind: nextConfig.gateway?.bind ?? "loopback",
      port: settings.port,
      customBindHost: nextConfig.gateway?.customBindHost,
      basePath: undefined,
    });
    // 守护进程安装/重启可能会短暂影响 WebSocket；等待一段时间，以便健康检查不会误报失败。
    await waitForGatewayReachable({
      url: probeLinks.wsUrl,
      token: settings.gatewayToken,
      deadlineMs: 15_000,
    });
    try {
      await healthCommand({ json: false, timeoutMs: 10_000 }, runtime);
    } catch (err) {
      runtime.error(formatHealthCheckFailure(err));
      await prompter.note(
        [
          "文档：",
          "https://docs.molt.bot/gateway/health",
          "https://docs.molt.bot/gateway/troubleshooting",
        ].join("\n"),
        "健康检查帮助",
      );
    }
  }

  const controlUiEnabled =
    nextConfig.gateway?.controlUi?.enabled ?? baseConfig.gateway?.controlUi?.enabled ?? true;
  if (!opts.skipUi && controlUiEnabled) {
    const controlUiAssets = await ensureControlUiAssetsBuilt(runtime);
    if (!controlUiAssets.ok && controlUiAssets.message) {
      runtime.error(controlUiAssets.message);
    }
  }

  await prompter.note(
    [
      "添加节点以获得额外功能：",
      "- macOS 应用（系统 + 通知）",
      "- iOS 应用（相机/画布）",
      "- Android 应用（相机/画布）",
    ].join("\n"),
    "可选应用",
  );

  const controlUiBasePath =
    nextConfig.gateway?.controlUi?.basePath ?? baseConfig.gateway?.controlUi?.basePath;
  const links = resolveControlUiLinks({
    bind: settings.bind,
    port: settings.port,
    customBindHost: settings.customBindHost,
    basePath: controlUiBasePath,
  });
  const tokenParam =
    settings.authMode === "token" && settings.gatewayToken
      ? `?token=${encodeURIComponent(settings.gatewayToken)}`
      : "";
  const authedUrl = `${links.httpUrl}${tokenParam}`;
  const gatewayProbe = await probeGatewayReachable({
    url: links.wsUrl,
    token: settings.authMode === "token" ? settings.gatewayToken : undefined,
    password: settings.authMode === "password" ? nextConfig.gateway?.auth?.password : "",
  });
  const gatewayStatusLine = gatewayProbe.ok
    ? "网关：可达"
    : `网关：未检测到${gatewayProbe.detail ? ` (${gatewayProbe.detail})` : ""}`;
  const bootstrapPath = path.join(
    resolveUserPath(options.workspaceDir),
    DEFAULT_BOOTSTRAP_FILENAME,
  );
  const hasBootstrap = await fs
    .access(bootstrapPath)
    .then(() => true)
    .catch(() => false);

  await prompter.note(
    [
      `Web UI：${links.httpUrl}`,
      tokenParam ? `Web UI（带令牌）：${authedUrl}` : undefined,
      `网关 WS：${links.wsUrl}`,
      gatewayStatusLine,
      "文档：https://docs.molt.bot/web/control-ui",
    ]
      .filter(Boolean)
      .join("\n"),
    "控制 UI",
  );

  let controlUiOpened = false;
  let controlUiOpenHint: string | undefined;
  let seededInBackground = false;
  let hatchChoice: "tui" | "web" | "later" | null = null;

  if (!opts.skipUi && gatewayProbe.ok) {
    if (hasBootstrap) {
      await prompter.note(
        [
          "这是定义您的智能体的决定性行动。",
          "请慢慢来。",
          "您告诉它的越多，体验就会越好。",
          '我们将发送："醒来吧，我的朋友！"',
        ].join("\n"),
        "启动 TUI（最佳选择！）",
      );
    }

    await prompter.note(
      [
        "网关令牌：网关 + 控制 UI 的共享认证。",
        "存储在：~/.clawdbot/moltbot.json (gateway.auth.token) 或 CLAWDBOT_GATEWAY_TOKEN。",
        "Web UI 将副本存储在此浏览器的 localStorage 中 (moltbot.control.settings.v1)。",
        `随时获取令牌化链接：${formatCliCommand("moltbot dashboard --no-open")}`,
      ].join("\n"),
      "令牌",
    );

    hatchChoice = (await prompter.select({
      message: "您想如何孵化您的机器人？",
      options: [
        { value: "tui", label: "在 TUI 中孵化（推荐）" },
        { value: "web", label: "打开 Web UI" },
        { value: "later", label: "稍后再做" },
      ],
      initialValue: "tui",
    })) as "tui" | "web" | "later";

    if (hatchChoice === "tui") {
      await runTui({
        url: links.wsUrl,
        token: settings.authMode === "token" ? settings.gatewayToken : undefined,
        password: settings.authMode === "password" ? nextConfig.gateway?.auth?.password : "",
        // 安全：入职 TUI 不应自动传递到 lastProvider/lastTo。
        deliver: false,
        message: hasBootstrap ? "醒来吧，我的朋友！" : undefined,
      });
      if (settings.authMode === "token" && settings.gatewayToken) {
        seededInBackground = await openUrlInBackground(authedUrl);
      }
      if (seededInBackground) {
        await prompter.note(
          `Web UI 在后台已启动。稍后使用：${formatCliCommand("moltbot dashboard --no-open")} 打开`,
          "Web UI",
        );
      }
    } else if (hatchChoice === "web") {
      const browserSupport = await detectBrowserOpenSupport();
      if (browserSupport.ok) {
        controlUiOpened = await openUrl(authedUrl);
        if (!controlUiOpened) {
          controlUiOpenHint = formatControlUiSshHint({
            port: settings.port,
            basePath: controlUiBasePath,
            token: settings.gatewayToken,
          });
        }
      } else {
        controlUiOpenHint = formatControlUiSshHint({
          port: settings.port,
          basePath: controlUiBasePath,
          token: settings.gatewayToken,
        });
      }
      await prompter.note(
        [
          `仪表板链接（带令牌）：${authedUrl}`,
          controlUiOpened
            ? "已在您的浏览器中打开。保持该标签页以控制 Moltbot。"
            : "在本机浏览器中复制/粘贴此 URL 以控制 Moltbot。",
          controlUiOpenHint,
        ]
          .filter(Boolean)
          .join("\n"),
        "仪表板就绪",
      );
    } else {
      await prompter.note(`准备就绪时：${formatCliCommand("moltbot dashboard --no-open")}`, "稍后");
    }
  } else if (opts.skipUi) {
    await prompter.note("跳过控制 UI/TUI 提示。", "控制 UI");
  }

  await prompter.note(
    ["备份您的智能体工作区。", "文档：https://docs.molt.bot/concepts/agent-workspace"].join("\n"),
    "工作区备份",
  );

  await prompter.note(
    "在您的计算机上运行智能体存在风险 — 加强您的设置：https://docs.molt.bot/security",
    "安全",
  );

  const shouldOpenControlUi =
    !opts.skipUi &&
    settings.authMode === "token" &&
    Boolean(settings.gatewayToken) &&
    hatchChoice === null;
  if (shouldOpenControlUi) {
    const browserSupport = await detectBrowserOpenSupport();
    if (browserSupport.ok) {
      controlUiOpened = await openUrl(authedUrl);
      if (!controlUiOpened) {
        controlUiOpenHint = formatControlUiSshHint({
          port: settings.port,
          basePath: controlUiBasePath,
          token: settings.gatewayToken,
        });
      }
    } else {
      controlUiOpenHint = formatControlUiSshHint({
        port: settings.port,
        basePath: controlUiBasePath,
        token: settings.gatewayToken,
      });
    }

    await prompter.note(
      [
        `仪表板链接（带令牌）：${authedUrl}`,
        controlUiOpened
          ? "已在您的浏览器中打开。保持该标签页以控制 Moltbot。"
          : "在本机浏览器中复制/粘贴此 URL 以控制 Moltbot。",
        controlUiOpenHint,
      ]
        .filter(Boolean)
        .join("\n"),
      "仪表板就绪",
    );
  }

  const webSearchKey = (nextConfig.tools?.web?.search?.apiKey ?? "").trim();
  const webSearchEnv = (process.env.BRAVE_API_KEY ?? "").trim();
  const hasWebSearchKey = Boolean(webSearchKey || webSearchEnv);
  await prompter.note(
    hasWebSearchKey
      ? [
          "Web 搜索已启用，因此您的智能体可以在需要时在线查找信息。",
          "",
          webSearchKey
            ? "API 密钥：存储在配置中 (tools.web.search.apiKey)。"
            : "API 密钥：通过 BRAVE_API_KEY 环境变量提供（网关环境）。",
          "文档：https://docs.molt.bot/tools/web",
        ].join("\n")
      : [
          "如果您希望您的智能体能够搜索网络，您需要一个 API 密钥。",
          "",
          "Moltbot 使用 Brave Search 作为 `web_search` 工具。没有 Brave Search API 密钥，Web 搜索将无法工作。",
          "",
          "交互式设置：",
          `- 运行：${formatCliCommand("moltbot configure --section web")}`,
          "- 启用 web_search 并粘贴您的 Brave Search API 密钥",
          "",
          "替代方案：在网关环境中设置 BRAVE_API_KEY（无需配置更改）。",
          "文档：https://docs.molt.bot/tools/web",
        ].join("\n"),
    "Web 搜索（可选）",
  );

  await prompter.note(
    '接下来做什么：https://molt.bot/showcase（"人们正在构建什么"）。',
    "接下来做什么",
  );

  await prompter.outro(
    controlUiOpened
      ? "入职完成。仪表板已使用您的令牌打开；保持该标签页以控制 Moltbot。"
      : seededInBackground
        ? "入职完成。Web UI 已在后台启动；随时使用上面的令牌化链接打开它。"
        : "入职完成。使用上面的令牌化仪表板链接来控制 Moltbot。",
  );
}
