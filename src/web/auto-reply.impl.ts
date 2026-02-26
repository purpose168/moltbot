/**
 * WhatsApp Web 自动回复实现导出文件
 * 整合并导出自动回复相关的核心功能和类型
 */

/**
 * 心跳相关导出
 * HEARTBEAT_PROMPT: 心跳提示文本
 * stripHeartbeatToken: 移除心跳令牌的函数
 */
export { HEARTBEAT_PROMPT, stripHeartbeatToken } from "../auto-reply/heartbeat.js";

/**
 * 令牌相关导出
 * HEARTBEAT_TOKEN: 心跳令牌
 * SILENT_REPLY_TOKEN: 静默回复令牌
 */
export { HEARTBEAT_TOKEN, SILENT_REPLY_TOKEN } from "../auto-reply/tokens.js";

/**
 * 常量导出
 * DEFAULT_WEB_MEDIA_BYTES: 默认的 Web 媒体字节大小
 */
export { DEFAULT_WEB_MEDIA_BYTES } from "./auto-reply/constants.js";

/**
 * 心跳运行器导出
 * resolveHeartbeatRecipients: 解析心跳接收者
 * runWebHeartbeatOnce: 运行一次 Web 心跳
 */
export { resolveHeartbeatRecipients, runWebHeartbeatOnce } from "./auto-reply/heartbeat-runner.js";

/**
 * 监控导出
 * monitorWebChannel: 监控 Web 通道的函数
 */
export { monitorWebChannel } from "./auto-reply/monitor.js";

/**
 * 类型导出
 * WebChannelStatus: Web 通道状态类型
 * WebMonitorTuning: Web 监控调优类型
 */
export type { WebChannelStatus, WebMonitorTuning } from "./auto-reply/types.js";
