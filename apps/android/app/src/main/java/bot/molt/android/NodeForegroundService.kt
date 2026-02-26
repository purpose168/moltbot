package bot.molt.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.PendingIntent
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * 节点前台服务
 * 负责显示持久通知以保持节点连接活跃
 */
class NodeForegroundService : Service() {
  private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private var notificationJob: Job? = null
  private var lastRequiresMic = false
  private var didStartForeground = false

  override fun onCreate() {
    super.onCreate()
    // 确保通知通道已创建
    ensureChannel()
    // 创建初始通知
    val initial = buildNotification(title = "Moltbot 节点", text = "启动中…")
    startForegroundWithTypes(notification = initial, requiresMic = false)

    val runtime = (application as NodeApp).runtime
    // 监听状态变化并更新通知
    notificationJob =
      scope.launch {
        combine(
          runtime.statusText,
          runtime.serverName,
          runtime.isConnected,
          runtime.voiceWakeMode,
          runtime.voiceWakeIsListening,
        ) { status, server, connected, voiceMode, voiceListening ->
          Quint(status, server, connected, voiceMode, voiceListening)
        }.collect { (status, server, connected, voiceMode, voiceListening) ->
          val title = if (connected) "Moltbot 节点 · 已连接" else "Moltbot 节点"
          val voiceSuffix =
            if (voiceMode == VoiceWakeMode.Always) {
              if (voiceListening) " · 语音唤醒: 监听中" else " · 语音唤醒: 已暂停"
            } else {
              ""
            }
          val text = (server?.let { "$status · $it" } ?: status) + voiceSuffix

          // 检查是否需要麦克风权限
          val requiresMic =
            voiceMode == VoiceWakeMode.Always && hasRecordAudioPermission()
          startForegroundWithTypes(
            notification = buildNotification(title = title, text = text),
            requiresMic = requiresMic,
          )
        }
      }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_STOP -> {
        // 处理停止操作
        (application as NodeApp).runtime.disconnect()
        stopSelf()
        return START_NOT_STICKY
      }
    }
    // 保持运行;连接由NodeRuntime管理(自动重连+手动)
    return START_STICKY
  }

  override fun onDestroy() {
    notificationJob?.cancel()
    scope.cancel()
    super.onDestroy()
  }

  override fun onBind(intent: Intent?) = null

  /**
   * 确保通知通道已创建
   */
  private fun ensureChannel() {
    val mgr = getSystemService(NotificationManager::class.java)
    val channel =
      NotificationChannel(
        CHANNEL_ID,
        "连接",
        NotificationManager.IMPORTANCE_LOW,
      ).apply {
        description = "Moltbot 节点连接状态"
        setShowBadge(false)
      }
    mgr.createNotificationChannel(channel)
  }

  /**
   * 构建通知
   */
  private fun buildNotification(title: String, text: String): Notification {
    val launchIntent = Intent(this, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val launchPending =
      PendingIntent.getActivity(
        this,
        1,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )

    val stopIntent = Intent(this, NodeForegroundService::class.java).setAction(ACTION_STOP)
    val stopPending =
      PendingIntent.getService(
        this,
        2,
        stopIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(text)
      .setContentIntent(launchPending)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .addAction(0, "断开连接", stopPending)
      .build()
  }

  /**
   * 更新通知
   */
  private fun updateNotification(notification: Notification) {
    val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    mgr.notify(NOTIFICATION_ID, notification)
  }

  /**
   * 使用指定类型启动前台服务
   */
  private fun startForegroundWithTypes(notification: Notification, requiresMic: Boolean) {
    if (didStartForeground && requiresMic == lastRequiresMic) {
      updateNotification(notification)
      return
    }

    lastRequiresMic = requiresMic
    val types =
      if (requiresMic) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
      } else {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
      }
    startForeground(NOTIFICATION_ID, notification, types)
    didStartForeground = true
  }

  /**
   * 检查是否有录音权限
   */
  private fun hasRecordAudioPermission(): Boolean {
    return (
      ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
        PackageManager.PERMISSION_GRANTED
    )
  }

  companion object {
    private const val CHANNEL_ID = "connection"
    private const val NOTIFICATION_ID = 1

    private const val ACTION_STOP = "bot.molt.android.action.STOP"

    /**
     * 启动前台服务
     */
    fun start(context: Context) {
      val intent = Intent(context, NodeForegroundService::class.java)
      context.startForegroundService(intent)
    }

    /**
     * 停止前台服务
     */
    fun stop(context: Context) {
      val intent = Intent(context, NodeForegroundService::class.java).setAction(ACTION_STOP)
      context.startService(intent)
    }
  }
}

/**
 * 五元组数据类
 */
private data class Quint<A, B, C, D, E>(val first: A, val second: B, val third: C, val fourth: D, val fifth: E)
