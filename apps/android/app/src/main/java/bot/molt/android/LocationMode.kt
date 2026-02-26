package bot.molt.android

/**
 * 位置模式枚举
 * 定义了不同的位置服务使用模式
 */
enum class LocationMode(val rawValue: String) {
  Off("off"),              // 关闭位置服务
  WhileUsing("whileUsing"), // 仅在使用时获取位置
  Always("always"),         // 始终获取位置
  ;

  companion object {
    /**
     * 从原始值创建位置模式实例
     * @param raw 原始字符串值
     * @return 对应的位置模式,如果无法匹配则返回 Off
     */
    fun fromRawValue(raw: String?): LocationMode {
      val normalized = raw?.trim()?.lowercase()
      return entries.firstOrNull { it.rawValue.lowercase() == normalized } ?: Off
    }
  }
}
