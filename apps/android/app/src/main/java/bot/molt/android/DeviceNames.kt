package bot.molt.android

import android.content.Context
import android.os.Build
import android.provider.Settings

/**
 * 设备名称工具对象
 * 用于获取和生成设备的默认名称
 */
object DeviceNames {
  /**
   * 获取最佳的默认节点名称
   * @param context 上下文对象
   * @return 设备名称,如果无法获取则返回默认值
   */
  fun bestDefaultNodeName(context: Context): String {
    // 尝试从系统设置中获取设备名称
    val deviceName =
      runCatching {
          Settings.Global.getString(context.contentResolver, "device_name")
        }
        .getOrNull()
        ?.trim()
        .orEmpty()

    // 如果设备名称不为空,直接返回
    if (deviceName.isNotEmpty()) return deviceName

    // 构建设备型号名称
    val model =
      listOfNotNull(Build.MANUFACTURER?.takeIf { it.isNotBlank() }, Build.MODEL?.takeIf { it.isNotBlank() })
        .joinToString(" ")
        .trim()

    // 如果无法获取型号信息,返回默认名称
    return model.ifEmpty { "Android 节点" }
  }
}
