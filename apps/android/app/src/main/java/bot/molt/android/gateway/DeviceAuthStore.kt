package bot.molt.android.gateway

import bot.molt.android.SecurePrefs

/**
 * 设备认证存储类
 * 负责管理设备令牌的存储和检索
 */
class DeviceAuthStore(private val prefs: SecurePrefs) {
  /**
   * 加载设备令牌
   * @param deviceId 设备ID
   * @param role 角色(node/operator)
   * @return 令牌字符串,如果不存在则返回null
   */
  fun loadToken(deviceId: String, role: String): String? {
    val key = tokenKey(deviceId, role)
    return prefs.getString(key)?.trim()?.takeIf { it.isNotEmpty() }
  }

  /**
   * 保存设备令牌
   * @param deviceId 设备ID
   * @param role 角色(node/operator)
   * @param token 令牌字符串
   */
  fun saveToken(deviceId: String, role: String, token: String) {
    val key = tokenKey(deviceId, role)
    prefs.putString(key, token.trim())
  }

  /**
   * 清除设备令牌
   * @param deviceId 设备ID
   * @param role 角色(node/operator)
   */
  fun clearToken(deviceId: String, role: String) {
    val key = tokenKey(deviceId, role)
    prefs.remove(key)
  }

  /**
   * 生成令牌存储键
   * @param deviceId 设备ID
   * @param role 角色
   * @return 标准化的存储键
   */
  private fun tokenKey(deviceId: String, role: String): String {
    val normalizedDevice = deviceId.trim().lowercase()
    val normalizedRole = role.trim().lowercase()
    return "gateway.deviceToken.$normalizedDevice.$normalizedRole"
  }
}
