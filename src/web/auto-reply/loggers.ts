import { createSubsystemLogger } from "../../logging/subsystem.js";

/**
 * WhatsApp 通道日志记录器
 * 用于记录 WhatsApp 通道的所有相关日志
 */
export const whatsappLog = createSubsystemLogger("gateway/channels/whatsapp");

/**
 * WhatsApp 入站消息日志记录器
 * 用于记录从 WhatsApp 接收到的消息
 */
export const whatsappInboundLog = whatsappLog.child("inbound");

/**
 * WhatsApp 出站消息日志记录器
 * 用于记录发送到 WhatsApp 的消息
 */
export const whatsappOutboundLog = whatsappLog.child("outbound");

/**
 * WhatsApp 心跳日志记录器
 * 用于记录 WhatsApp 连接的心跳检测
 */
export const whatsappHeartbeatLog = whatsappLog.child("heartbeat");
