package bot.molt.android

/**
 * 规范化主密钥
 * @param raw 原始主密钥字符串
 * @return 规范化后的主密钥,如果为空则返回"main"
 */
internal fun normalizeMainKey(raw: String?): String {
  val trimmed = raw?.trim()
  return if (!trimmed.isNullOrEmpty()) trimmed else "main"
}

/**
 * 检查是否为规范的主会话密钥
 * @param raw 原始主会话密钥字符串
 * @return 如果是规范的主会话密钥则返回true
 */
internal fun isCanonicalMainSessionKey(raw: String?): Boolean {
  val trimmed = raw?.trim().orEmpty()
  if (trimmed.isEmpty()) return false
  if (trimmed == "global") return true
  return trimmed.startsWith("agent:")
}
