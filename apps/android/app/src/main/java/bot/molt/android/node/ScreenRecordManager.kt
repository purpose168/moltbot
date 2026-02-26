package bot.molt.android.node

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaRecorder
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Base64
import bot.molt.android.ScreenCaptureRequester
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.roundToInt

/**
 * 屏幕录制管理器
 * 负责录制屏幕内容
 */
class ScreenRecordManager(private val context: Context) {
  /**
   * 屏幕录制负载数据类
   * @param payloadJson 屏幕录制信息的JSON字符串
   */
  data class Payload(val payloadJson: String)

  @Volatile private var screenCaptureRequester: ScreenCaptureRequester? = null
  @Volatile private var permissionRequester: bot.molt.android.PermissionRequester? = null

  /**
   * 附加屏幕捕获请求器
   */
  fun attachScreenCaptureRequester(requester: ScreenCaptureRequester) {
    screenCaptureRequester = requester
  }

  /**
   * 附加权限请求器
   */
  fun attachPermissionRequester(requester: bot.molt.android.PermissionRequester) {
    permissionRequester = requester
  }

  /**
   * 录制屏幕
   * @param paramsJson 参数JSON字符串
   * @return 屏幕录制负载数据
   */
  suspend fun record(paramsJson: String?): Payload =
    withContext(Dispatchers.Default) {
      val requester =
        screenCaptureRequester
          ?: throw IllegalStateException(
            "SCREEN_PERMISSION_REQUIRED: 请授予屏幕录制权限",
          )

      // 解析参数
      val durationMs = (parseDurationMs(paramsJson) ?: 10_000).coerceIn(250, 60_000)
      val fps = (parseFps(paramsJson) ?: 10.0).coerceIn(1.0, 60.0)
      val fpsInt = fps.roundToInt().coerceIn(1, 60)
      val screenIndex = parseScreenIndex(paramsJson)
      val includeAudio = parseIncludeAudio(paramsJson) ?: true
      val format = parseString(paramsJson, key = "format")
      if (format != null && format.lowercase() != "mp4") {
        throw IllegalArgumentException("INVALID_REQUEST: 屏幕格式必须是mp4")
      }
      if (screenIndex != null && screenIndex != 0) {
        throw IllegalArgumentException("INVALID_REQUEST: Android上screenIndex必须为0")
      }

      // 请求屏幕捕获权限
      val capture = requester.requestCapture()
        ?: throw IllegalStateException(
          "SCREEN_PERMISSION_REQUIRED: 请授予屏幕录制权限",
        )

      val mgr =
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
      val projection = mgr.getMediaProjection(capture.resultCode, capture.data)
        ?: throw IllegalStateException("UNAVAILABLE: 屏幕捕获不可用")

      // 获取屏幕尺寸
      val metrics = context.resources.displayMetrics
      val width = metrics.widthPixels
      val height = metrics.heightPixels
      val densityDpi = metrics.densityDpi

      // 创建临时文件
      val file = File.createTempFile("moltbot-screen-", ".mp4")
      if (includeAudio) ensureMicPermission()

      val recorder = createMediaRecorder()
      var virtualDisplay: android.hardware.display.VirtualDisplay? = null
      try {
        // 配置录制器
        if (includeAudio) {
          recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        }
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        if (includeAudio) {
          recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
          recorder.setAudioChannels(1)
          recorder.setAudioSamplingRate(44_100)
          recorder.setAudioEncodingBitRate(96_000)
        }
        recorder.setVideoSize(width, height)
        recorder.setVideoFrameRate(fpsInt)
        recorder.setVideoEncodingBitRate(estimateBitrate(width, height, fpsInt))
        recorder.setOutputFile(file.absolutePath)
        recorder.prepare()

        // 创建虚拟显示器
        val surface = recorder.surface
        virtualDisplay =
          projection.createVirtualDisplay(
            "moltbot-screen",
            width,
            height,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            null,
          )

        // 开始录制
        recorder.start()
        delay(durationMs.toLong())
      } finally {
        // 清理资源
        try {
          recorder.stop()
        } catch (_: Throwable) {
          // 忽略
        }
        recorder.reset()
        recorder.release()
        virtualDisplay?.release()
        projection.stop()
      }

      // 读取并编码视频文件
      val bytes = withContext(Dispatchers.IO) { file.readBytes() }
      file.delete()
      val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
      Payload(
        """{"format":"mp4","base64":"$base64","durationMs":$durationMs,"fps":$fpsInt,"screenIndex":0,"hasAudio":$includeAudio}""",
      )
    }

  /**
   * 创建媒体录制器
   */
  private fun createMediaRecorder(): MediaRecorder = MediaRecorder(context)

  /**
   * 确保有麦克风权限
   */
  private suspend fun ensureMicPermission() {
    val granted =
      androidx.core.content.ContextCompat.checkSelfPermission(
        context,
        android.Manifest.permission.RECORD_AUDIO,
      ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    if (granted) return

    val requester =
      permissionRequester
        ?: throw IllegalStateException("MIC_PERMISSION_REQUIRED: 请授予麦克风权限")
    val results = requester.requestIfMissing(listOf(android.Manifest.permission.RECORD_AUDIO))
    if (results[android.Manifest.permission.RECORD_AUDIO] != true) {
      throw IllegalStateException("MIC_PERMISSION_REQUIRED: 请授予麦克风权限")
    }
  }

  /**
   * 解析持续时间(毫秒)
   */
  private fun parseDurationMs(paramsJson: String?): Int? =
    parseNumber(paramsJson, key = "durationMs")?.toIntOrNull()

  /**
   * 解析帧率
   */
  private fun parseFps(paramsJson: String?): Double? =
    parseNumber(paramsJson, key = "fps")?.toDoubleOrNull()

  /**
   * 解析屏幕索引
   */
  private fun parseScreenIndex(paramsJson: String?): Int? =
    parseNumber(paramsJson, key = "screenIndex")?.toIntOrNull()

  /**
   * 解析是否包含音频
   */
  private fun parseIncludeAudio(paramsJson: String?): Boolean? {
    val raw = paramsJson ?: return null
    val key = "\"includeAudio\""
    val idx = raw.indexOf(key)
    if (idx < 0) return null
    val colon = raw.indexOf(':', idx + key.length)
    if (colon < 0) return null
    val tail = raw.substring(colon + 1).trimStart()
    return when {
      tail.startsWith("true") -> true
      tail.startsWith("false") -> false
      else -> null
    }
  }

  /**
   * 解析数字参数
   */
  private fun parseNumber(paramsJson: String?, key: String): String? {
    val raw = paramsJson ?: return null
    val needle = "\"$key\""
    val idx = raw.indexOf(needle)
    if (idx < 0) return null
    val colon = raw.indexOf(':', idx + needle.length)
    if (colon < 0) return null
    val tail = raw.substring(colon + 1).trimStart()
    return tail.takeWhile { it.isDigit() || it == '.' || it == '-' }
  }

  /**
   * 解析字符串参数
   */
  private fun parseString(paramsJson: String?, key: String): String? {
    val raw = paramsJson ?: return null
    val needle = "\"$key\""
    val idx = raw.indexOf(needle)
    if (idx < 0) return null
    val colon = raw.indexOf(':', idx + needle.length)
    if (colon < 0) return null
    val tail = raw.substring(colon + 1).trimStart()
    if (!tail.startsWith('\"')) return null
    val rest = tail.drop(1)
    val end = rest.indexOf('\"')
    if (end < 0) return null
    return rest.substring(0, end)
  }

  /**
   * 估算比特率
   */
  private fun estimateBitrate(width: Int, height: Int, fps: Int): Int {
    val pixels = width.toLong() * height.toLong()
    val raw = (pixels * fps.toLong() * 2L).toInt()
    return raw.coerceIn(1_000_000, 12_000_000)
  }
}
