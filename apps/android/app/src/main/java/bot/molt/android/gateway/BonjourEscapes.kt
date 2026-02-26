package bot.molt.android.gateway

/**
 * Bonjour转义工具对象
 * 负责解码Bonjour服务名称中的转义字符
 */
object BonjourEscapes {
  /**
   * 解码Bonjour字符串
   * 处理八进制转义序列(如\123)
   * @param input 输入字符串
   * @return 解码后的字符串
   */
  fun decode(input: String): String {
    if (input.isEmpty()) return input

    val bytes = mutableListOf<Byte>()
    var i = 0
    while (i < input.length) {
      // 检查八进制转义序列
      if (input[i] == '\\' && i + 3 < input.length) {
        val d0 = input[i + 1]
        val d1 = input[i + 2]
        val d2 = input[i + 3]
        // 验证是否为有效的八进制数字
        if (d0.isDigit() && d1.isDigit() && d2.isDigit()) {
          val value =
            ((d0.code - '0'.code) * 100) + ((d1.code - '0'.code) * 10) + (d2.code - '0'.code)
          if (value in 0..255) {
            bytes.add(value.toByte())
            i += 4
            continue
          }
        }
      }

      // 处理普通字符
      val codePoint = Character.codePointAt(input, i)
      val charBytes = String(Character.toChars(codePoint)).toByteArray(Charsets.UTF_8)
      for (b in charBytes) {
        bytes.add(b)
      }
      i += Character.charCount(codePoint)
    }

    return String(bytes.toByteArray(), Charsets.UTF_8)
  }
}
