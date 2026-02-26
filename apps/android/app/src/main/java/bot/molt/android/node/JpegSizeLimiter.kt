package bot.molt.android.node

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * JPEG大小限制器结果数据类
 * @param bytes 压缩后的字节数组
 * @param width 图像宽度
 * @param height 图像高度
 * @param quality JPEG质量(1-100)
 */
internal data class JpegSizeLimiterResult(
  val bytes: ByteArray,
  val width: Int,
  val height: Int,
  val quality: Int,
)

/**
 * JPEG大小限制器工具对象
 * 用于将JPEG图像压缩到指定大小限制内
 */
internal object JpegSizeLimiter {
  /**
   * 压缩图像到指定大小限制
   * @param initialWidth 初始宽度
   * @param initialHeight 初始高度
   * @param startQuality 起始质量(1-100)
   * @param maxBytes 最大字节数
   * @param minQuality 最小质量(默认20)
   * @param minSize 最小尺寸(默认256)
   * @param scaleStep 缩放步长(默认0.85)
   * @param maxScaleAttempts 最大缩放尝试次数(默认6)
   * @param maxQualityAttempts 最大质量调整尝试次数(默认6)
   * @param encode 编码函数
   * @return 压缩结果
   */
  fun compressToLimit(
    initialWidth: Int,
    initialHeight: Int,
    startQuality: Int,
    maxBytes: Int,
    minQuality: Int = 20,
    minSize: Int = 256,
    scaleStep: Double = 0.85,
    maxScaleAttempts: Int = 6,
    maxQualityAttempts: Int = 6,
    encode: (width: Int, height: Int, quality: Int) -> ByteArray,
  ): JpegSizeLimiterResult {
    require(initialWidth > 0 && initialHeight > 0) { "无效的图像尺寸" }
    require(maxBytes > 0) { "无效的maxBytes" }

    var width = initialWidth
    var height = initialHeight
    val clampedStartQuality = startQuality.coerceIn(minQuality, 100)
    // 首先尝试使用起始质量压缩
    var best = JpegSizeLimiterResult(bytes = encode(width, height, clampedStartQuality), width = width, height = height, quality = clampedStartQuality)
    if (best.bytes.size <= maxBytes) return best

    // 通过降低质量和缩放来减小文件大小
    repeat(maxScaleAttempts) {
      var quality = clampedStartQuality
      repeat(maxQualityAttempts) {
        val bytes = encode(width, height, quality)
        best = JpegSizeLimiterResult(bytes = bytes, width = width, height = height, quality = quality)
        if (bytes.size <= maxBytes) return best
        if (quality <= minQuality) return@repeat
        // 降低质量
        quality = max(minQuality, (quality * 0.75).roundToInt())
      }

      // 计算缩放比例
      val minScale = (minSize.toDouble() / min(width, height).toDouble()).coerceAtMost(1.0)
      val nextScale = max(scaleStep, minScale)
      val nextWidth = max(minSize, (width * nextScale).roundToInt())
      val nextHeight = max(minSize, (height * nextScale).roundToInt())
      if (nextWidth == width && nextHeight == height) return@repeat
      width = min(nextWidth, width)
      height = min(nextHeight, height)
    }

    // 如果仍然超出限制,抛出异常
    if (best.bytes.size > maxBytes) {
      throw IllegalStateException("CAMERA_TOO_LARGE: ${best.bytes.size} 字节 > $maxBytes 字节")
    }

    return best
  }
}
