# Moltbot macOS 应用（开发 + 签名）

## 快速开发运行

```bash
# 从仓库根目录
scripts/restart-mac.sh
```

选项：

```bash
scripts/restart-mac.sh --no-sign   # 最快的开发方式；临时签名（TCC 权限不会保持）
scripts/restart-mac.sh --sign      # 强制代码签名（需要证书）
```

## 打包流程

```bash
scripts/package-mac-app.sh
```

创建 `dist/Moltbot.app` 并通过 `scripts/codesign-mac-app.sh` 进行签名。

## 签名行为

自动选择身份（优先匹配）：
1) Developer ID Application
2) Apple Distribution
3) Apple Development
4) 第一个可用身份

如果未找到：
- 默认报错
- 设置 `ALLOW_ADHOC_SIGNING=1` 或 `SIGN_IDENTITY="-"` 进行临时签名

## Team ID 审核（Sparkle 不匹配保护）

签名后，我们会读取应用包的 Team ID 并比较应用内的每个 Mach-O 文件。
如果任何嵌入的二进制文件有不同的 Team ID，签名将失败。

跳过审核：
```bash
SKIP_TEAM_ID_CHECK=1 scripts/package-mac-app.sh
```

## 库验证解决方案（仅开发用）

如果 Sparkle Team ID 不匹配阻止加载（在 Apple Development 证书中常见），可以选择：

```bash
DISABLE_LIBRARY_VALIDATION=1 scripts/package-mac-app.sh
```

这会将 `com.apple.security.cs.disable-library-validation` 添加到应用权限中。
仅用于本地开发；发布构建时请保持关闭。

## 有用的环境标志

- `SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"`
- `ALLOW_ADHOC_SIGNING=1`（临时签名，TCC 权限不会持久）
- `CODESIGN_TIMESTAMP=off`（离线调试）
- `DISABLE_LIBRARY_VALIDATION=1`（仅开发用的 Sparkle 解决方案）
- `SKIP_TEAM_ID_CHECK=1`（绕过审核）
