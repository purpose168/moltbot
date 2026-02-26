package bot.molt.android

import android.content.pm.PackageManager
import android.content.Intent
import android.Manifest
import android.net.Uri
import android.provider.Settings
import androidx.appcompat.app.AlertDialog
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * 权限请求器
 * 负责处理运行时权限请求
 */
class PermissionRequester(private val activity: ComponentActivity) {
  private val mutex = Mutex()
  private var pending: CompletableDeferred<Map<String, Boolean>>? = null

  private val launcher: ActivityResultLauncher<Array<String>> =
    activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
      val p = pending
      pending = null
      p?.complete(result)
    }

  /**
   * 如果缺少权限则请求
   * @param permissions 需要检查的权限列表
   * @param timeoutMs 超时时间(毫秒)
   * @return 权限名称到授权状态的映射
   */
  suspend fun requestIfMissing(
    permissions: List<String>,
    timeoutMs: Long = 20_000,
  ): Map<String, Boolean> =
    mutex.withLock {
      // 筛选出未授予的权限
      val missing =
        permissions.filter { perm ->
          ContextCompat.checkSelfPermission(activity, perm) != PackageManager.PERMISSION_GRANTED
        }
      if (missing.isEmpty()) {
        return permissions.associateWith { true }
      }

      // 检查是否需要显示说明对话框
      val needsRationale =
        missing.any { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
      if (needsRationale) {
        val proceed = showRationaleDialog(missing)
        if (!proceed) {
          return permissions.associateWith { perm ->
            ContextCompat.checkSelfPermission(activity, perm) == PackageManager.PERMISSION_GRANTED
          }
        }
      }

      // 请求权限
      val deferred = CompletableDeferred<Map<String, Boolean>>()
      pending = deferred
      withContext(Dispatchers.Main) {
        launcher.launch(missing.toTypedArray())
      }

      // 等待权限请求结果
      val result =
        withContext(Dispatchers.Default) {
          kotlinx.coroutines.withTimeout(timeoutMs) { deferred.await() }
        }

      // 合并结果:如果权限已授予,即使启动器省略了也视为已授予
      val merged =
        permissions.associateWith { perm ->
          val nowGranted =
            ContextCompat.checkSelfPermission(activity, perm) == PackageManager.PERMISSION_GRANTED
          result[perm] == true || nowGranted
        }

      // 检查被永久拒绝的权限
      val denied =
        merged.filterValues { !it }.keys.filter {
          !ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
        }
      if (denied.isNotEmpty()) {
        showSettingsDialog(denied)
      }

      return merged
    }

  /**
   * 显示权限说明对话框
   */
  private suspend fun showRationaleDialog(permissions: List<String>): Boolean =
    withContext(Dispatchers.Main) {
      suspendCancellableCoroutine { cont ->
        AlertDialog.Builder(activity)
          .setTitle("需要权限")
          .setMessage(buildRationaleMessage(permissions))
          .setPositiveButton("继续") { _, _ -> cont.resume(true) }
          .setNegativeButton("暂不") { _, _ -> cont.resume(false) }
          .setOnCancelListener { cont.resume(false) }
          .show()
      }
    }

  /**
   * 显示设置对话框
   */
  private fun showSettingsDialog(permissions: List<String>) {
    AlertDialog.Builder(activity)
      .setTitle("在设置中启用权限")
      .setMessage(buildSettingsMessage(permissions))
      .setPositiveButton("打开设置") { _, _ ->
        val intent =
          Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
          )
        activity.startActivity(intent)
      }
      .setNegativeButton("取消", null)
      .show()
  }

  /**
   * 构建权限说明消息
   */
  private fun buildRationaleMessage(permissions: List<String>): String {
    val labels = permissions.map { permissionLabel(it) }
    return "Moltbot 需要 ${labels.joinToString(", ")} 权限才能继续。"
  }

  /**
   * 构建设置消息
   */
  private fun buildSettingsMessage(permissions: List<String>): String {
    val labels = permissions.map { permissionLabel(it) }
    return "请在 Android 设置中启用 ${labels.joinToString(", ")} 以继续。"
  }

  /**
   * 获取权限标签
   */
  private fun permissionLabel(permission: String): String =
    when (permission) {
      Manifest.permission.CAMERA -> "相机"
      Manifest.permission.RECORD_AUDIO -> "麦克风"
      Manifest.permission.SEND_SMS -> "短信"
      else -> permission
    }
}
