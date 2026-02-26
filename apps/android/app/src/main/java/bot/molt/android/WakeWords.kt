package bot.molt.android

/**
 * 唤醒词工具对象
 * 负责解析和验证唤醒词
 */
object WakeWords {
  const val maxWords: Int = 32        // 最大唤醒词数量
  const val maxWordLength: Int = 64    // 单个唤醒词最大长度

  /**
   * 解析逗号分隔的唤醒词
   * @param input 输入字符串
   * @return 唤醒词列表
   */
  fun parseCommaSeparated(input: String): List<String> {
    return input.split(",").map { it.trim() }.filter { it.isNotEmpty() }
  }

  /**
   * 解析并检查是否有变化
   * @param input 输入字符串
   * @param current 当前唤醒词列表
   * @return 如果有变化则返回新列表,否则返回null
   */
  fun parseIfChanged(input: String, current: List<String>): List<String>? {
    val parsed = parseCommaSeparated(input)
    return if (parsed == current) null else parsed
  }

  /**
   * 清理和验证唤醒词
   * @param words 原始唤醒词列表
   * @param defaults 默认唤醒词列表
   * @return 清理后的唤醒词列表,如果为空则返回默认值
   */
  fun sanitize(words: List<String>, defaults: List<String>): List<String> {
    val cleaned =
      words.map { it.trim() }.filter { it.isNotEmpty() }.take(maxWords).map { it.take(maxWordLength) }
    return cleaned.ifEmpty { defaults }
  }
}
