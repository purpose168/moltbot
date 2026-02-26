/**
 * 解析后的 vCard 类型
 *
 * @property name 联系人姓名（可选）
 * @property phones 电话号码数组
 */
type ParsedVcard = {
  name?: string;
  phones: string[];
};

/**
 * 允许的 vCard 键集合
 */
const ALLOWED_VCARD_KEYS = new Set(["FN", "N", "TEL"]);

/**
 * 解析 vCard 字符串
 *
 * @param vcard vCard 格式的字符串（可选）
 * @returns 解析后的 vCard 对象
 */
export function parseVcard(vcard?: string): ParsedVcard {
  if (!vcard) return { phones: [] };
  const lines = vcard.split(/\r?\n/);
  let nameFromN: string | undefined;
  let nameFromFn: string | undefined;
  const phones: string[] = [];
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;
    const colonIndex = line.indexOf(":");
    if (colonIndex === -1) continue;
    const key = line.slice(0, colonIndex).toUpperCase();
    const rawValue = line.slice(colonIndex + 1).trim();
    if (!rawValue) continue;
    const baseKey = normalizeVcardKey(key);
    if (!baseKey || !ALLOWED_VCARD_KEYS.has(baseKey)) continue;
    const value = cleanVcardValue(rawValue);
    if (!value) continue;
    if (baseKey === "FN" && !nameFromFn) {
      nameFromFn = normalizeVcardName(value);
      continue;
    }
    if (baseKey === "N" && !nameFromN) {
      nameFromN = normalizeVcardName(value);
      continue;
    }
    if (baseKey === "TEL") {
      const phone = normalizeVcardPhone(value);
      if (phone) phones.push(phone);
    }
  }
  return { name: nameFromFn ?? nameFromN, phones };
}

/**
 * 标准化 vCard 键
 *
 * @param key vCard 键
 * @returns 标准化后的键
 */
function normalizeVcardKey(key: string): string | undefined {
  const [primary] = key.split(";");
  if (!primary) return undefined;
  const segments = primary.split(".");
  return segments[segments.length - 1] || undefined;
}

/**
 * 清理 vCard 值
 *
 * @param value vCard 值
 * @returns 清理后的值
 */
function cleanVcardValue(value: string): string {
  return value.replace(/\\n/gi, " ").replace(/\\,/g, ",").replace(/\\;/g, ";").trim();
}

/**
 * 标准化 vCard 姓名
 *
 * @param value 姓名值
 * @returns 标准化后的姓名
 */
function normalizeVcardName(value: string): string {
  return value.replace(/;/g, " ").replace(/\s+/g, " ").trim();
}

/**
 * 标准化 vCard 电话号码
 *
 * @param value 电话号码值
 * @returns 标准化后的电话号码
 */
function normalizeVcardPhone(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (trimmed.toLowerCase().startsWith("tel:")) {
    return trimmed.slice(4).trim();
  }
  return trimmed;
}
