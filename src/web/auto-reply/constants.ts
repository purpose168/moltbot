/**
 * 默认的 Web 媒体大小限制
 * 设置为 5MB（5 * 1024 * 1024 字节）
 *
 * @description
 * 此常量用于限制通过 WhatsApp Web 发送的媒体文件大小，
 * 确保发送的媒体文件不会超过 WhatsApp 的大小限制，
 * 同时避免发送过大的文件导致网络传输问题。
 */
export const DEFAULT_WEB_MEDIA_BYTES = 5 * 1024 * 1024;
