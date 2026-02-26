import { randomToken } from "../commands/onboard-helpers.js";
import type { GatewayAuthChoice } from "../commands/onboard-types.js";
import type { MoltbotConfig } from "../config/config.js";
import { findTailscaleBinary } from "../infra/tailscale.js";
import type { RuntimeEnv } from "../runtime.js";
import type {
  GatewayWizardSettings,
  QuickstartGatewayDefaults,
  WizardFlow,
} from "./onboarding.types.js";
import type { WizardPrompter } from "./prompts.js";

/**
 * 配置网关选项类型
 */
type ConfigureGatewayOptions = {
  /** 向导流程 */
  flow: WizardFlow;
  /** 基础配置 */
  baseConfig: MoltbotConfig;
  /** 下一步配置 */
  nextConfig: MoltbotConfig;
  /** 本地端口 */
  localPort: number;
  /** 快速启动网关默认值 */
  quickstartGateway: QuickstartGatewayDefaults;
  /** 提示器 */
  prompter: WizardPrompter;
  /** 运行时环境 */
  runtime: RuntimeEnv;
};

/**
 * 配置网关结果类型
 */
type ConfigureGatewayResult = {
  /** 下一步配置 */
  nextConfig: MoltbotConfig;
  /** 网关设置 */
  settings: GatewayWizardSettings;
};

/**
 * 为入职配置网关
 */
export async function configureGatewayForOnboarding(
  opts: ConfigureGatewayOptions,
): Promise<ConfigureGatewayResult> {
  const { flow, localPort, quickstartGateway, prompter } = opts;
  let { nextConfig } = opts;

  /**
   * 网关端口
   */
  const port =
    flow === "quickstart"
      ? quickstartGateway.port
      : Number.parseInt(
          String(
            await prompter.text({
              message: "网关端口",
              initialValue: String(localPort),
              validate: (value) => (Number.isFinite(Number(value)) ? undefined : "无效端口"),
            }),
          ),
          10,
        );

  /**
   * 网关绑定
   */
  let bind = (
    flow === "quickstart"
      ? quickstartGateway.bind
      : ((await prompter.select({
          message: "网关绑定",
          options: [
            { value: "loopback", label: "环回 (127.0.0.1)" },
            { value: "lan", label: "局域网 (0.0.0.0)" },
            { value: "tailnet", label: "Tailnet (Tailscale IP)" },
            { value: "auto", label: "自动 (环回 → 局域网)" },
            { value: "custom", label: "自定义 IP" },
          ],
        })) as "loopback" | "lan" | "auto" | "custom" | "tailnet")
  ) as "loopback" | "lan" | "auto" | "custom" | "tailnet";

  /**
   * 自定义绑定主机
   */
  let customBindHost = quickstartGateway.customBindHost;
  if (bind === "custom") {
    const needsPrompt = flow !== "quickstart" || !customBindHost;
    if (needsPrompt) {
      const input = await prompter.text({
        message: "自定义 IP 地址",
        placeholder: "192.168.1.100",
        initialValue: customBindHost ?? "",
        validate: (value) => {
          if (!value) return "自定义绑定模式需要 IP 地址";
          const trimmed = value.trim();
          const parts = trimmed.split(".");
          if (parts.length !== 4) return "无效的 IPv4 地址（例如，192.168.1.100）";
          if (
            parts.every((part) => {
              const n = parseInt(part, 10);
              return !Number.isNaN(n) && n >= 0 && n <= 255 && part === String(n);
            })
          )
            return undefined;
          return "无效的 IPv4 地址（每个八位字节必须为 0-255）";
        },
      });
      customBindHost = typeof input === "string" ? input.trim() : undefined;
    }
  }

  /**
   * 网关认证模式
   */
  let authMode = (
    flow === "quickstart"
      ? quickstartGateway.authMode
      : ((await prompter.select({
          message: "网关认证",
          options: [
            {
              value: "token",
              label: "令牌",
              hint: "推荐默认值（本地 + 远程）",
            },
            { value: "password", label: "密码" },
          ],
          initialValue: "token",
        })) as GatewayAuthChoice)
  ) as GatewayAuthChoice;

  /**
   * Tailscale 暴露模式
   */
  const tailscaleMode = (
    flow === "quickstart"
      ? quickstartGateway.tailscaleMode
      : ((await prompter.select({
          message: "Tailscale 暴露",
          options: [
            { value: "off", label: "关闭", hint: "无 Tailscale 暴露" },
            {
              value: "serve",
              label: "服务",
              hint: "为您的 tailnet（Tailscale 上的设备）提供私有 HTTPS",
            },
            {
              value: "funnel",
              label: "漏斗",
              hint: "通过 Tailscale Funnel 提供公共 HTTPS（互联网）",
            },
          ],
        })) as "off" | "serve" | "funnel")
  ) as "off" | "serve" | "funnel";

  // 在继续 serve/funnel 设置之前检测 Tailscale 二进制文件。
  if (tailscaleMode !== "off") {
    const tailscaleBin = await findTailscaleBinary();
    if (!tailscaleBin) {
      await prompter.note(
        [
          "在 PATH 或 /Applications 中未找到 Tailscale 二进制文件。",
          "确保从以下位置安装 Tailscale：",
          "  https://tailscale.com/download/mac",
          "",
          "您可以继续设置，但 serve/funnel 在运行时会失败。",
        ].join("\n"),
        "Tailscale 警告",
      );
    }
  }

  /**
   * 退出时重置 Tailscale
   */
  let tailscaleResetOnExit = flow === "quickstart" ? quickstartGateway.tailscaleResetOnExit : false;
  if (tailscaleMode !== "off" && flow !== "quickstart") {
    await prompter.note(
      ["文档：", "https://docs.molt.bot/gateway/tailscale", "https://docs.molt.bot/web"].join("\n"),
      "Tailscale",
    );
    tailscaleResetOnExit = Boolean(
      await prompter.confirm({
        message: "退出时重置 Tailscale serve/funnel？",
        initialValue: false,
      }),
    );
  }

  // 安全 + 约束：
  // - Tailscale 要求 bind=loopback，因此我们永远不会同时暴露非环回服务器和 tailscale serve/funnel。
  // - Funnel 需要密码认证。
  if (tailscaleMode !== "off" && bind !== "loopback") {
    await prompter.note("Tailscale 要求 bind=loopback。将 bind 调整为 loopback。", "注意");
    bind = "loopback";
    customBindHost = undefined;
  }

  if (tailscaleMode === "funnel" && authMode !== "password") {
    await prompter.note("Tailscale funnel 需要密码认证。", "注意");
    authMode = "password";
  }

  /**
   * 网关令牌
   */
  let gatewayToken: string | undefined;
  if (authMode === "token") {
    if (flow === "quickstart") {
      gatewayToken = quickstartGateway.token ?? randomToken();
    } else {
      const tokenInput = await prompter.text({
        message: "网关令牌（留空生成）",
        placeholder: "多机器或非环回访问需要",
        initialValue: quickstartGateway.token ?? "",
      });
      gatewayToken = String(tokenInput).trim() || randomToken();
    }
  }

  if (authMode === "password") {
    const password =
      flow === "quickstart" && quickstartGateway.password
        ? quickstartGateway.password
        : await prompter.text({
            message: "网关密码",
            validate: (value) => (value?.trim() ? undefined : "必填"),
          });
    nextConfig = {
      ...nextConfig,
      gateway: {
        ...nextConfig.gateway,
        auth: {
          ...nextConfig.gateway?.auth,
          mode: "password",
          password: String(password).trim(),
        },
      },
    };
  } else if (authMode === "token") {
    nextConfig = {
      ...nextConfig,
      gateway: {
        ...nextConfig.gateway,
        auth: {
          ...nextConfig.gateway?.auth,
          mode: "token",
          token: gatewayToken,
        },
      },
    };
  }

  nextConfig = {
    ...nextConfig,
    gateway: {
      ...nextConfig.gateway,
      port,
      bind,
      ...(bind === "custom" && customBindHost ? { customBindHost } : {}),
      tailscale: {
        ...nextConfig.gateway?.tailscale,
        mode: tailscaleMode,
        resetOnExit: tailscaleResetOnExit,
      },
    },
  };

  return {
    nextConfig,
    settings: {
      port,
      bind,
      customBindHost: bind === "custom" ? customBindHost : undefined,
      authMode,
      gatewayToken,
      tailscaleMode,
      tailscaleResetOnExit,
    },
  };
}
