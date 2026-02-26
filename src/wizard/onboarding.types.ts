import type { GatewayAuthChoice } from "../commands/onboard-types.js";

/**
 * 向导流程类型
 */
export type WizardFlow = "quickstart" | "advanced";

/**
 * 快速启动网关默认值类型
 */
export type QuickstartGatewayDefaults = {
  /** 是否已有配置 */
  hasExisting: boolean;
  /** 端口 */
  port: number;
  /** 绑定方式 */
  bind: "loopback" | "lan" | "auto" | "custom" | "tailnet";
  /** 认证模式 */
  authMode: GatewayAuthChoice;
  /** Tailscale 模式 */
  tailscaleMode: "off" | "serve" | "funnel";
  /** 令牌 */
  token?: string;
  /** 密码 */
  password?: string;
  /** 自定义绑定主机 */
  customBindHost?: string;
  /** 退出时重置 Tailscale */
  tailscaleResetOnExit: boolean;
};

/**
 * 网关向导设置类型
 */
export type GatewayWizardSettings = {
  /** 端口 */
  port: number;
  /** 绑定方式 */
  bind: "loopback" | "lan" | "auto" | "custom" | "tailnet";
  /** 自定义绑定主机 */
  customBindHost?: string;
  /** 认证模式 */
  authMode: GatewayAuthChoice;
  /** 网关令牌 */
  gatewayToken?: string;
  /** Tailscale 模式 */
  tailscaleMode: "off" | "serve" | "funnel";
  /** 退出时重置 Tailscale */
  tailscaleResetOnExit: boolean;
};
