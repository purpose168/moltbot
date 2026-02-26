package bot.molt.android

/**
 * 相机 HUD 状态类型枚举
 */
enum class CameraHudKind {
  Photo,      // 照片模式
  Recording,  // 录制模式
  Success,    // 成功状态
  Error,      // 错误状态
}

/**
 * 相机 HUD 状态数据类
 * @param token 令牌标识
 * @param kind HUD 状态类型
 * @param message 显示消息
 */
data class CameraHudState(
  val token: Long,              // 令牌标识
  val kind: CameraHudKind,      // HUD 状态类型
  val message: String,          // 显示消息
)
