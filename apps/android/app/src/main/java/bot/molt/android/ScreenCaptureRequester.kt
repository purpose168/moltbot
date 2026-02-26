package bot.molt.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * 屏幕捕获请求器
 * 负责请求屏幕录制权限
 */
class ScreenCaptureRequester(private val activity: ComponentActivity) {
  data class CaptureResult(val resultCode: Int, val data: Intent)

  private val mutex = Mutex()
  private var pending: CompletableDeferred<CaptureResult?>? = null

  private val launcher: ActivityResultLauncher<Intent> =
    activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
      val p = pending
      pending = null
      val data = result.data
      if (result.resultCode == Activity.RESULT_OK && data != null) {
        p?.complete(CaptureResult(result.resultCode, data))
      } else {
        p?.complete(null)
      }
    }

  /**
   * 请求屏幕捕获
   * @param timeoutMs 超时时间(毫秒)
   * @return 捕获结果,如果被拒绝则返回null
   */
  suspend fun requestCapture(timeoutMs: Long = 20_000): CaptureResult? =
    mutex.withLock {
      val proceed = showRationaleDialog()
      if (!proceed) return null

      val mgr = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
      val intent = mgr.createScreenCaptureIntent()

      val deferred = CompletableDeferred<CaptureResult?>()
      pending = deferred
      withContext(Dispatchers.Main) { launcher.launch(intent) }
      withContext(Dispatchers.Default) { withTimeout(timeoutMs) { deferred.await() } }
    }

  /**
   * 显示权限说明对话框
   */
  private suspend fun showRationaleDialog(): Boolean =
    withContext(Dispatchers.Main) {
      suspendCancellableCoroutine { cont ->
        AlertDialog.Builder(activity)
          .setTitle("需要屏幕录制")
          .setMessage("Moltbot 需要录制屏幕以执行此命令。")
          .setPositiveButton("继续") { _, _ -> cont.resume(true) }
          .setNegativeButton("暂不") { _, _ -> cont.resume(false) }
          .setOnCancelListener { cont.resume(false) }
          .show()
      }
    }
}
