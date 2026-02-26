# 安全策略

如果您认为您在 Moltbot 中发现了安全问题,请私下报告。

## 报告

- 邮箱: `steipete@gmail.com`
- 包括的内容: 复现步骤、影响评估,以及(如果可能)最小的 PoC。

## 运维指南

有关威胁模型 + 加固指南(包括 `moltbot security audit --deep` 和 `--fix`),请参阅:

- `https://docs.molt.bot/gateway/security`

### Web 界面安全

Moltbot 的 Web 界面仅用于本地使用。请**不要**将其绑定到公共互联网;它没有针对公共暴露进行加固。

## 运行时要求

### Node.js 版本

Moltbot 需要 **Node.js 22.12.0 或更高版本**(LTS)。此版本包含重要的安全补丁:

- CVE-2025-59466: async_hooks DoS 漏洞
- CVE-2026-21636: 权限模型绕过漏洞

验证您的 Node.js 版本:

```bash
node --version  # 应该是 v22.12.0 或更高版本
```

### Docker 安全

在 Docker 中运行 Moltbot 时:

1. 官方镜像以非 root 用户(`node`)运行,以减少攻击面
2. 尽可能使用 `--read-only` 标志以获得额外的文件系统保护
3. 使用 `--cap-drop=ALL` 限制容器能力

安全 Docker 运行示例:

```bash
docker run --read-only --cap-drop=ALL \
  -v moltbot-data:/app/data \
  moltbot/moltbot:latest
```

## 安全扫描

此项目使用 `detect-secrets` 在 CI/CD 中进行自动密钥检测。
有关配置,请参阅 `.detect-secrets.cfg`;有关基线,请参阅 `.secrets.baseline`。

本地运行:

```bash
pip install detect-secrets==1.5.0
detect-secrets scan --baseline .secrets.baseline
```
