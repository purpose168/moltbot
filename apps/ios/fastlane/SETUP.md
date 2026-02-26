# fastlane 配置 (Moltbot iOS)

安装：

```bash
brew install fastlane
```

创建 App Store Connect API 密钥：

- App Store Connect → 用户和访问权限 → 密钥 → App Store Connect API → 生成 API 密钥
- 下载 `.p8` 文件，记录下 **Issuer ID** 和 **Key ID**

创建 `apps/ios/fastlane/.env` 文件（已被 git 忽略）：

```bash
ASC_KEY_ID=YOUR_KEY_ID
ASC_ISSUER_ID=YOUR_ISSUER_ID
ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8

# 代码签名（Apple 团队 ID / App ID 前缀）
IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

提示：从仓库根目录运行 `scripts/ios-team-id.sh` 可以打印出团队 ID，以便粘贴到 `.env` 文件中。如果缺少 `IOS_DEVELOPMENT_TEAM`，Fastlane 会使用这个辅助脚本。

运行：

```bash
cd apps/ios
fastlane beta
```
