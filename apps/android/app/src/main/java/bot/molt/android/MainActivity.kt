package bot.molt.android

import android.Manifest
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Build
import android.view.WindowManager
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import bot.molt.android.ui.RootScreen
import bot.molt.android.ui.MoltbotTheme
import kotlinx.coroutines.launch

/**
 * 主活动类
 * 负责应用的初始化、权限请求和UI设置
 */
class MainActivity : ComponentActivity() {
  private val viewModel: MainViewModel by viewModels()
  private lateinit var permissionRequester: PermissionRequester
  private lateinit var screenCaptureRequester: ScreenCaptureRequester

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // 启用WebView调试(仅在调试模式下)
    val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    WebView.setWebContentsDebuggingEnabled(isDebuggable)
    // 应用沉浸式模式
    applyImmersiveMode()
    // 请求必要的权限
    requestDiscoveryPermissionsIfNeeded()
    requestNotificationPermissionIfNeeded()
    // 启动前台服务
    NodeForegroundService.start(this)
    // 初始化权限请求器
    permissionRequester = PermissionRequester(this)
    screenCaptureRequester = ScreenCaptureRequester(this)
    // 附加生命周期和权限处理器
    viewModel.camera.attachLifecycleOwner(this)
    viewModel.camera.attachPermissionRequester(permissionRequester)
    viewModel.sms.attachPermissionRequester(permissionRequester)
    viewModel.screenRecorder.attachScreenCaptureRequester(screenCaptureRequester)
    viewModel.screenRecorder.attachPermissionRequester(permissionRequester)

    // 监听防睡眠设置
    lifecycleScope.launch {
      repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.preventSleep.collect { enabled ->
          if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          }
        }
      }
    }

    // 设置Compose UI
    setContent {
      MoltbotTheme {
        Surface(modifier = Modifier) {
          RootScreen(viewModel = viewModel)
        }
      }
    }
  }

  override fun onResume() {
    super.onResume()
    applyImmersiveMode()
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (hasFocus) {
      applyImmersiveMode()
    }
  }

  override fun onStart() {
    super.onStart()
    viewModel.setForeground(true)
  }

  override fun onStop() {
    viewModel.setForeground(false)
    super.onStop()
  }

  /**
   * 应用沉浸式模式(隐藏系统栏)
   */
  private fun applyImmersiveMode() {
    WindowCompat.setDecorFitsSystemWindows(window, false)
    val controller = WindowInsetsControllerCompat(window, window.decorView)
    controller.systemBarsBehavior =
      WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    controller.hide(WindowInsetsCompat.Type.systemBars())
  }

  /**
   * 请求设备发现权限(根据Android版本)
   */
  private fun requestDiscoveryPermissionsIfNeeded() {
    if (Build.VERSION.SDK_INT >= 33) {
      // Android 13+: 请求NEARBY_WIFI_DEVICES权限
      val ok =
        ContextCompat.checkSelfPermission(
          this,
          Manifest.permission.NEARBY_WIFI_DEVICES,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
      if (!ok) {
        requestPermissions(arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES), 100)
      }
    } else {
      // Android 12及以下: 请求ACCESS_FINE_LOCATION权限
      val ok =
        ContextCompat.checkSelfPermission(
          this,
          Manifest.permission.ACCESS_FINE_LOCATION,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
      if (!ok) {
        requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), 101)
      }
    }
  }

  /**
   * 请求通知权限(Android 13+)
   */
  private fun requestNotificationPermissionIfNeeded() {
    if (Build.VERSION.SDK_INT < 33) return
    val ok =
      ContextCompat.checkSelfPermission(
        this,
        Manifest.permission.POST_NOTIFICATIONS,
      ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    if (!ok) {
      requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 102)
    }
  }
}
