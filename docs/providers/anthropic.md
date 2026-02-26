---
summary: "在 Moltbot 中通过 API 密钥或 setup-token 使用 Anthropic Claude"
read_when:
  - 您想在 Moltbot 中使用 Anthropic 模型
  - 您想使用 setup-token 而不是 API 密钥
---
# Anthropic (Claude)

Anthropic 构建了 **Claude** 模型系列并通过 API 提供访问。
在 Moltbot 中，您可以使用 API 密钥或 **setup-token** 进行身份验证。

## 选项 A: Anthropic API 密钥

**最适合：** 标准 API 访问和基于使用量的计费。
在 Anthropic Console 中创建您的 API 密钥。

### CLI 设置

```bash
moltbot onboard
# 选择: Anthropic API key

# 或非交互式
moltbot onboard --anthropic-api-key "$ANTHROPIC_API_KEY"
```

### 配置片段

```json5
{
  env: { ANTHROPIC_API_KEY: "sk-ant-..." },
  agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } }
}
```

## 提示缓存 (Anthropic API)

Moltbot **不会**覆盖 Anthropic 的默认缓存 TTL，除非您设置了它。
这仅适用于 **API**；订阅身份验证不遵守 TTL 设置。

要为每个模型设置 TTL，请在模型 `params` 中使用 `cacheControlTtl`：

```json5
{
  agents: {
    defaults: {
      models: {
        "anthropic/claude-opus-4-5": {
          params: { cacheControlTtl: "5m" } // 或 "1h"
        }
      }
    }
  }
}
```

Moltbot 包含 `extended-cache-ttl-2025-04-11` beta 标志，用于 Anthropic API 请求；
如果您覆盖了提供商标头，请保留它（参见 [/gateway/configuration](/gateway/configuration)）。

## 选项 B: Claude setup-token

**最适合：** 使用您的 Claude 订阅。

### 在哪里获取 setup-token

Setup-token 由 **Claude Code CLI** 创建，而不是 Anthropic Console。您可以在**任何机器**上运行此命令：

```bash
claude setup-token
```

将令牌粘贴到 Moltbot 中（向导：**Anthropic token (paste setup-token)**），或在网关主机上运行：

```bash
moltbot models auth setup-token --provider anthropic
```

如果您在不同的机器上生成了令牌，请粘贴它：

```bash
moltbot models auth paste-token --provider anthropic
```

### CLI 设置

```bash
# 在引导过程中粘贴 setup-token
moltbot onboard --auth-choice setup-token
```

### 配置片段

```json5
{
  agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } }
}
```

## 注意事项

- 使用 `claude setup-token` 生成 setup-token 并粘贴它，或在网关主机上运行 `moltbot models auth setup-token`。
- 如果您在 Claude 订阅上看到 "OAuth token refresh failed …"，请使用 setup-token 重新进行身份验证。参见 [/gateway/troubleshooting#oauth-token-refresh-failed-anthropic-claude-subscription](/gateway/troubleshooting#oauth-token-refresh-failed-anthropic-claude-subscription)。
- 身份验证详细信息 + 重用规则在 [/concepts/oauth](/concepts/oauth) 中。

## 故障排除

**401 错误 / 令牌突然无效**
- Claude 订阅身份验证可能已过期或被撤销。重新运行 `claude setup-token`
  并将其粘贴到**网关主机**。
- 如果 Claude CLI 登录位于不同的机器上，请使用
  `moltbot models auth paste-token --provider anthropic` 在网关主机上。

**未找到提供商 "anthropic" 的 API 密钥**
- 身份验证是**每个智能体**的。新智能体不会继承主智能体的密钥。
- 为该智能体重新运行引导，或在网关主机上粘贴 setup-token / API 密钥，
  然后使用 `moltbot models status` 进行验证。

**未找到配置文件 `anthropic:default` 的凭据**
- 运行 `moltbot models status` 查看哪个身份验证配置文件处于活动状态。
- 重新运行引导，或为该配置文件粘贴 setup-token / API 密钥。

**没有可用的身份验证配置文件（全部处于冷却/不可用状态）**
- 检查 `moltbot models status --json` 中的 `auth.unusableProfiles`。
- 添加另一个 Anthropic 配置文件或等待冷却结束。

更多信息：[/gateway/troubleshooting](/gateway/troubleshooting) 和 [/help/faq](/help/faq)。
