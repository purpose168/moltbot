package bot.molt.android

import android.app.Application
import android.os.StrictMode

/**
 * 节点应用类
 * 应用程序的入口点,负责初始化运行时
 */
class NodeApp : Application() {
  // 懒加载的运行时实例
  val runtime: NodeRuntime by lazy { NodeRuntime(this) }

  override fun onCreate() {
    super.onCreate()
    // 在调试模式下启用严格模式以检测问题
    if (BuildConfig.DEBUG) {
      StrictMode.setThreadPolicy(
        StrictMode.ThreadPolicy.Builder()
          .detectAll()
          .penaltyLog()
          .build(),
      )
      StrictMode.setVmPolicy(
        StrictMode.VmPolicy.Builder()
          .detectAll()
          .penaltyLog()
          .build(),
      )
    }
  }
}
