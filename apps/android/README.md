## Clawdbot 节点 (Android) (内部)

现代 Android 节点应用:连接到 **Gateway WebSocket** (`_clawdbot-gw._tcp`) 并暴露 **Canvas + Chat + Camera** 功能。

注意事项:
- 节点通过 **前台服务** 保持连接活跃(带有断开操作的持久通知)
- 聊天始终使用共享会话密钥 **`main`** (在 iOS/macOS/WebChat/Android 之间使用相同的会话)
- 仅支持现代 Android (`minSdk 31`, Kotlin + Jetpack Compose)

## 在 Android Studio 中打开
- 打开文件夹 `apps/android`

## 构建 / 运行

```bash
cd apps/android
./gradlew :app:assembleDebug
./gradlew :app:installDebug
./gradlew :app:testDebugUnitTest
```

如果未设置 `ANDROID_SDK_ROOT` / `ANDROID_HOME`,`gradlew` 会自动检测 `~/Library/Android/sdk` (macOS 默认路径) 中的 Android SDK。

## 连接 / 配对

1) 启动网关(在您的"主控"机器上):
```bash
pnpm clawdbot gateway --port 18789 --verbose
```

2) 在 Android 应用中:
- 打开 **设置**
- 在 **发现的网关** 下选择一个已发现的网关,或使用 **高级 → 手动网关**(主机 + 端口)

3) 批准配对(在网关机器上):
```bash
clawdbot nodes pending
clawdbot nodes approve <requestId>
```

更多详情: `docs/platforms/android.md`

## 权限

- 发现:
  - Android 13+ (`API 33+`): `NEARBY_WIFI_DEVICES`
  - Android 12 及以下: `ACCESS_FINE_LOCATION` (NSD 扫描所需)
- 前台服务通知 (Android 13+): `POST_NOTIFICATIONS`
- 相机:
  - `CAMERA` 用于 `camera.snap` 和 `camera.clip`
  - `RECORD_AUDIO` 用于 `camera.clip` 当 `includeAudio=true` 时
