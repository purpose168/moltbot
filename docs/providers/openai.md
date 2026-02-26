---
summary: "在 Moltbot 中通过 API 密钥或 Codex 订阅使用 OpenAI"
read_when:
  - 您想在 Moltbot 中使用 OpenAI 模型
  - 您想使用 Codex 订阅身份验证而不是 API 密钥
---
# OpenAI

OpenAI 为 GPT 模型提供开发者 API。Codex 支持 **ChatGPT 登录**以进行订阅访问，
或使用 **API 密钥**登录以进行基于使用量的访问。Codex 云需要 ChatGPT 登录。

## 选项 A: OpenAI API 密钥 (OpenAI Platform)

**最适合：** 直接 API 访问和基于使用量的计费。
从 OpenAI 仪表板获取您的 API 密钥。

### CLI 设置

```bash
moltbot onboard --auth-choice openai-api-key
# 或非交互式
moltbot onboard --openai-api-key "$OPENAI_API_KEY"
```

### 配置片段

```json5
{
  env: { OPENAI_API_KEY: "sk-..." },
  agents: { defaults: { model: { primary: "openai/gpt-5.2" } } }
}
```

## 选项 B: OpenAI Code (Codex) 订阅

**最适合：** 使用 ChatGPT/Codex 订阅访问而不是 API 密钥。
Codex 云需要 ChatGPT 登录，而 Codex CLI 支持 ChatGPT 或 API 密钥登录。

### CLI 设置

```bash
# 在向导中运行 Codex OAuth
moltbot onboard --auth-choice openai-codex

# 或直接运行 OAuth
moltbot models auth login --provider openai-codex
```

### 配置片段

```json5
{
  agents: { defaults: { model: { primary: "openai-codex/gpt-5.2" } } }
}
```

## 注意事项

- 模型引用始终使用 `provider/model`（参见 [/concepts/models](/concepts/models)）。
- 身份验证详细信息 + 重用规则在 [/concepts/oauth](/concepts/oauth) 中。
