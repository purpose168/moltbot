---
summary: "初学者指南：从零到第一条消息（向导、认证、频道、配对）"
read_when:
  - 首次从零开始设置
  - 您希望以最快的路径从安装 → 引导 → 第一条消息
---

# 入门指南

目标：尽可能快地从**零** → **第一个正常工作的聊天**（使用合理的默认设置）。

最快的聊天方式：打开控制 UI（无需频道设置）。运行 `moltbot dashboard` 并在浏览器中聊天，或在网关节点上打开 `http://127.0.0.1:18789/`。
文档：[仪表板](/web/dashboard) 和 [控制 UI](/web/control-ui)。

推荐路径：使用**命令行引导向导**（`moltbot onboard`）。它会设置：
- 模型/认证（推荐使用 OAuth）
- 网关设置
- 频道（WhatsApp/Telegram/Discord/Mattermost（插件）/...）
- 配对默认值（安全私信）
- 工作区引导 + 技能
- 可选的后台服务

如果您需要更深入的参考页面，请跳转到：[向导](/start/wizard)、[设置](/start/setup)、[配对](/start/pairing)、[安全](/gateway/security)。

沙箱说明：`agents.defaults.sandbox.mode: "non-main"` 使用 `session.mainKey`（默认值 `"main"`），
因此群组/频道会话会被沙箱隔离。如果您希望主智能体始终
在主机上运行，请设置明确的智能体覆盖：

```json
{
  "routing": {
    "agents": {
      "main": {
        "workspace": "~/clawd",
        "sandbox": { "mode": "off" }
      }
    }
  }
}
```

## 0) 前提条件

- Node `>=22`
- `pnpm`（可选；如果从源代码构建，建议使用）
- **推荐：** 用于网络搜索的 Brave Search API 密钥。最简单的路径：
  `moltbot configure --section web`（存储 `tools.web.search.apiKey`）。
  请参阅 [Web 工具](/tools/web)。

macOS：如果您计划构建应用程序，请安装 Xcode / CLT。对于仅 CLI + 网关，Node 就足够了。
Windows：使用**WSL2**（推荐 Ubuntu）。强烈推荐 WSL2；原生 Windows 未经测试，问题更多，且工具兼容性更差。首先安装 WSL2，然后在 WSL 内运行 Linux 步骤。请参阅 [Windows (WSL2)](/platforms/windows)。

## 1) 安装 CLI（推荐）

```bash
curl -fsSL https://molt.bot/install.sh | bash
```

安装程序选项（安装方法、非交互式、从 GitHub）：[安装](/install)。

Windows（PowerShell）：

```powershell
iwr -useb https://molt.bot/install.ps1 | iex
```

替代方案（全局安装）：

```bash
npm install -g moltbot@latest
```

```bash
pnpm add -g moltbot@latest
```

## 2) 运行引导向导（并安装服务）

```bash
moltbot onboard --install-daemon
```

您将选择：
- **本地 vs 远程** 网关
- **认证**：OpenAI Code（Codex）订阅（OAuth）或 API 密钥。对于 Anthropic，我们推荐 API 密钥；也支持 `claude setup-token`。
- **提供商**：WhatsApp QR 登录、Telegram/Discord 机器人令牌、Mattermost 插件令牌等。
- **守护进程**：后台安装（launchd/systemd；WSL2 使用 systemd）
  - **运行时**：Node（推荐；WhatsApp/Telegram 必需）。**不推荐**使用 Bun。
- **网关令牌**：向导默认会生成一个（即使在回环网络上）并将其存储在 `gateway.auth.token` 中。

向导文档：[向导](/start/wizard)

### 认证：存储位置（重要）

- **推荐的 Anthropic 路径：** 设置 API 密钥（向导可以为服务使用存储它）。如果您想重用 Claude Code 凭据，也支持 `claude setup-token`。

- OAuth 凭据（旧版导入）：`~/.clawdbot/credentials/oauth.json`
- 认证配置文件（OAuth + API 密钥）：`~/.clawdbot/agents/<agentId>/agent/auth-profiles.json`

无头/服务器提示：首先在普通机器上进行 OAuth，然后将 `oauth.json` 复制到网关节点。

## 3) 启动网关

如果您在引导过程中安装了服务，网关应该已经在运行：

```bash
moltbot gateway status
```

手动运行（前台）：

```bash
moltbot gateway --port 18789 --verbose
```

仪表板（本地回环）：`http://127.0.0.1:18789/`
如果配置了令牌，请将其粘贴到控制 UI 设置中（存储为 `connect.params.auth.token`）。

⚠️ **Bun 警告（WhatsApp + Telegram）：** Bun 在这些
频道上存在已知问题。如果您使用 WhatsApp 或 Telegram，请使用**Node**运行网关。

## 3.5) 快速验证（2 分钟）

```bash
moltbot status
moltbot health
moltbot security audit --deep
```

## 4) 配对并连接您的第一个聊天界面

### WhatsApp（QR 登录）

```bash
moltbot channels login
```

通过 WhatsApp → 设置 → 链接设备进行扫描。

WhatsApp 文档：[WhatsApp](/channels/whatsapp)

### Telegram / Discord / 其他

向导可以为您写入令牌/配置。如果您更喜欢手动配置，请从以下开始：
- Telegram：[Telegram](/channels/telegram)
- Discord：[Discord](/channels/discord)
- Mattermost（插件）：[Mattermost](/channels/mattermost)

**Telegram 私信提示：** 您的第一条私信会返回一个配对代码。请批准它（见下一步），否则机器人不会响应。

## 5) 私信安全（配对批准）

默认姿态：未知私信会收到一个短代码，消息在批准前不会被处理。
如果您的第一条私信没有回复，请批准配对：

```bash
moltbot pairing list whatsapp
moltbot pairing approve whatsapp <code>
```

配对文档：[配对](/start/pairing)

## 从源代码（开发）

如果您正在修改 Moltbot 本身，请从源代码运行：

```bash
git clone https://github.com/moltbot/moltbot.git
cd moltbot
pnpm install
pnpm ui:build # 首次运行时自动安装 UI 依赖
pnpm build
moltbot onboard --install-daemon
```

如果您还没有全局安装，请通过 `pnpm moltbot ...` 从仓库运行引导步骤。
`pnpm build` 还会打包 A2UI 资产；如果您只需要运行该步骤，请使用 `pnpm canvas:a2ui:bundle`。

网关（从本仓库）：

```bash
node moltbot.mjs gateway --port 18789 --verbose
```

## 7) 端到端验证

在新终端中，发送测试消息：

```bash
moltbot message send --target +15555550123 --message "Hello from Moltbot"
```

如果 `moltbot health` 显示 "no auth configured"，请返回向导并设置 OAuth/密钥认证 — 没有它，智能体将无法响应。

提示：`moltbot status --all` 是最好的可粘贴、只读调试报告。
健康探测：`moltbot health`（或 `moltbot status --deep`）向运行中的网关请求健康快照。

## 后续步骤（可选，但很棒）

- macOS 菜单栏应用 + 语音唤醒：[macOS 应用](/platforms/macos)
- iOS/Android 节点（画布/摄像头/语音）：[节点](/nodes)
- 远程访问（SSH 隧道 / Tailscale Serve）：[远程访问](/gateway/remote) 和 [Tailscale](/gateway/tailscale)
- 始终在线 / VPN 设置：[远程访问](/gateway/remote)、[exe.dev](/platforms/exe-dev)、[Hetzner](/platforms/hetzner)、[macOS 远程](/platforms/mac/remote)
