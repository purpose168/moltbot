/**
 * WhatsApp Web 自动回复工具函数
 *
 * 此模块提供了与 WhatsApp Web 自动回复相关的工具函数，
 * 包括文本处理、错误检测等功能。
 */

/**
 * 截断文本
 *
 * 将长文本截断到指定长度，并在末尾添加省略号和截断信息。
 *
 * @param text - 要截断的文本（可选）
 * @param limit - 截断长度，默认 400 个字符
 * @returns 截断后的文本，如果输入为 null 或 undefined 则返回原值
 */
export function elide(text?: string, limit = 400) {
  if (!text) return text;
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}… (已截断 ${text.length - limit} 个字符)`;
}

/**
 * 检测是否为 WhatsApp 加密错误
 *
 * 用于判断错误是否与 WhatsApp 加密相关，
 * 主要用于识别需要特殊处理的加密认证错误。
 *
 * @param reason - 错误原因
 * @returns 是否为 WhatsApp 加密错误
 */
export function isLikelyWhatsAppCryptoError(reason: unknown) {
  /**
   * 格式化错误原因
   *
   * 将各种类型的错误原因转换为字符串格式，
   * 以便于后续的错误信息分析。
   *
   * @param value - 要格式化的值
   * @returns 格式化后的字符串
   */
  const formatReason = (value: unknown): string => {
    if (value == null) return "";
    if (typeof value === "string") return value;
    if (value instanceof Error) {
      return `${value.message}\n${value.stack ?? ""}`;
    }
    if (typeof value === "object") {
      try {
        return JSON.stringify(value);
      } catch {
        return Object.prototype.toString.call(value);
      }
    }
    if (typeof value === "number") return String(value);
    if (typeof value === "boolean") return String(value);
    if (typeof value === "bigint") return String(value);
    if (typeof value === "symbol") return value.description ?? value.toString();
    if (typeof value === "function") return value.name ? `[function ${value.name}]` : "[function]";
    return Object.prototype.toString.call(value);
  };

  // 处理错误原因，转换为字符串格式并转为小写
  const raw =
    reason instanceof Error ? `${reason.message}\n${reason.stack ?? ""}` : formatReason(reason);
  const haystack = raw.toLowerCase();

  // 检查是否包含认证错误信息
  const hasAuthError =
    haystack.includes("unsupported state or unable to authenticate data") ||
    haystack.includes("bad mac");
  if (!hasAuthError) return false;

  // 检查是否与 WhatsApp/Baileys 相关
  return (
    haystack.includes("@whiskeysockets/baileys") ||
    haystack.includes("baileys") ||
    haystack.includes("noise-handler") ||
    haystack.includes("aesdecryptgcm")
  );
}
