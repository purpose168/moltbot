package bot.molt.android.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * 位置捕获管理器
 * 负责获取设备位置信息
 */
class LocationCaptureManager(private val context: Context) {
  /**
   * 位置负载数据类
   * @param payloadJson 位置信息的JSON字符串
   */
  data class Payload(val payloadJson: String)

  /**
   * 获取位置信息
   * @param desiredProviders 期望的位置提供者列表
   * @param maxAgeMs 最大缓存时间(毫秒)
   * @param timeoutMs 超时时间(毫秒)
   * @param isPrecise 是否为精确位置
   * @return 位置负载数据
   */
  suspend fun getLocation(
    desiredProviders: List<String>,
    maxAgeMs: Long?,
    timeoutMs: Long,
    isPrecise: Boolean,
  ): Payload =
    withContext(Dispatchers.Main) {
      val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
      // 检查是否有可用的位置提供者
      if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
        !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
      ) {
        throw IllegalStateException("LOCATION_UNAVAILABLE: 没有启用的位置提供者")
      }

      // 尝试获取缓存的位置或请求新的位置
      val cached = bestLastKnown(manager, desiredProviders, maxAgeMs)
      val location =
        cached ?: requestCurrent(manager, desiredProviders, timeoutMs)

      // 格式化时间戳
      val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(location.time))
      val source = location.provider
      val altitudeMeters = if (location.hasAltitude()) location.altitude else null
      val speedMps = if (location.hasSpeed()) location.speed.toDouble() else null
      val headingDeg = if (location.hasBearing()) location.bearing.toDouble() else null
      // 构建位置信息的JSON字符串
      Payload(
        buildString {
          append("{\"lat\":")
          append(location.latitude)
          append(",\"lon\":")
          append(location.longitude)
          append(",\"accuracyMeters\":")
          append(location.accuracy.toDouble())
          if (altitudeMeters != null) append(",\"altitudeMeters\":").append(altitudeMeters)
          if (speedMps != null) append(",\"speedMps\":").append(speedMps)
          if (headingDeg != null) append(",\"headingDeg\":").append(headingDeg)
          append(",\"timestamp\":\"").append(timestamp).append('"')
          append(",\"isPrecise\":").append(isPrecise)
          append(",\"source\":\"").append(source).append('"')
          append('}')
        },
      )
    }

  /**
   * 获取最佳缓存位置
   * @param manager 位置管理器
   * @param providers 位置提供者列表
   * @param maxAgeMs 最大缓存时间(毫秒)
   * @return 最佳缓存位置,如果不符合条件则返回null
   */
  private fun bestLastKnown(
    manager: LocationManager,
    providers: List<String>,
    maxAgeMs: Long?,
  ): Location? {
    // 检查位置权限
    val fineOk =
      ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    val coarseOk =
      ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    if (!fineOk && !coarseOk) {
      throw IllegalStateException("LOCATION_PERMISSION_REQUIRED: 请授予位置权限")
    }
    val now = System.currentTimeMillis()
    // 获取所有提供者的最新位置
    val candidates =
      providers.mapNotNull { provider -> manager.getLastKnownLocation(provider) }
    val freshest = candidates.maxByOrNull { it.time } ?: return null
    // 检查缓存是否过期
    if (maxAgeMs != null && now - freshest.time > maxAgeMs) return null
    return freshest
  }

  /**
   * 请求当前位置
   * @param manager 位置管理器
   * @param providers 位置提供者列表
   * @param timeoutMs 超时时间(毫秒)
   * @return 当前位置
   */
  private suspend fun requestCurrent(
    manager: LocationManager,
    providers: List<String>,
    timeoutMs: Long,
  ): Location {
    // 检查位置权限
    val fineOk =
      ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    val coarseOk =
      ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    if (!fineOk && !coarseOk) {
      throw IllegalStateException("LOCATION_PERMISSION_REQUIRED: 请授予位置权限")
    }
    // 找到第一个可用的位置提供者
    val resolved =
      providers.firstOrNull { manager.isProviderEnabled(it) }
        ?: throw IllegalStateException("LOCATION_UNAVAILABLE: 没有可用的位置提供者")
    return withTimeout(timeoutMs.coerceAtLeast(1)) {
      suspendCancellableCoroutine { cont ->
        val signal = CancellationSignal()
        cont.invokeOnCancellation { signal.cancel() }
        manager.getCurrentLocation(resolved, signal, context.mainExecutor) { location ->
          if (location != null) {
            cont.resume(location)
          } else {
            cont.resumeWithException(IllegalStateException("LOCATION_UNAVAILABLE: 无法获取位置"))
          }
        }
      }
    }
  }
}
