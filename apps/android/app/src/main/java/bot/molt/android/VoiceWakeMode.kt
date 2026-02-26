package bot.molt.android

/**
 * 语音唤醒模式枚举
 * 定义了语音唤醒的不同使用模式
 */
enum class VoiceWakeMode(val rawValue: String) {
  Off("off"),              // 关闭语音唤醒
  Foreground("foreground"), // 仅在前台时启用
  Always("always"),         // 始终启用
  ;

  companion object {
    /**
     * 从原始值创建语音唤醒模式实例
     * @param raw 原始字符串值
     * @return 对应的语音唤醒模式,如果无法匹配则返回 Foreground
     */
    fun fromRawValue(raw: String?): VoiceWakeMode {
      return entries.firstOrNull { it.rawValue == raw?.trim()?.lowercase() } ?: Foreground
    }
  }
}
