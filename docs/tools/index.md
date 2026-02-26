---
summary: "Moltbot 的智能体工具表面（浏览器、画布、节点、消息、定时任务），替代旧版 `moltbot-*` 技能"
read_when:
  - 添加或修改智能体工具
  - 淘汰或更改 `moltbot-*` 技能
---

# 工具（Moltbot）

Moltbot 为浏览器、画布、节点和定时任务提供**一流的智能体工具**。
这些工具替代了旧的 `moltbot-*` 技能：它们是类型化的，无需 shell 操作，
智能体应该直接依赖它们。

## 禁用工具

您可以通过 `moltbot.json` 中的 `tools.allow` / `tools.deny` 全局允许/拒绝工具
（拒绝优先）。这可以防止被拒绝的工具被发送到模型提供商。

```json5
{
  tools: { deny: ["browser"] }
}
```

注意：
- 匹配不区分大小写。
- 支持 `*` 通配符（`"*"` 表示所有工具）。
- 如果 `tools.allow` 仅引用未知或未加载的插件工具名称，Moltbot 会记录警告并忽略允许列表，以便核心工具保持可用。

## 工具配置文件（基础允许列表）

`tools.profile` 在 `tools.allow`/`tools.deny` 之前设置**基础工具允许列表**。
每个智能体覆盖：`agents.list[].tools.profile`。

配置文件：
- `minimal`：仅 `session_status`
- `coding`：`group:fs`、`group:runtime`、`group:sessions`、`group:memory`、`image`
- `messaging`：`group:messaging`、`sessions_list`、`sessions_history`、`sessions_send`、`session_status`
- `full`：无限制（与未设置相同）

示例（默认仅消息传递，也允许 Slack + Discord 工具）：
```json5
{
  tools: {
    profile: "messaging",
    allow: ["slack", "discord"]
  }
}
```

示例（编码配置文件，但在各处拒绝 exec/process）：
```json5
{
  tools: {
    profile: "coding",
    deny: ["group:runtime"]
  }
}
```

示例（全局编码配置文件，仅消息传递支持智能体）：
```json5
{
  tools: { profile: "coding" },
  agents: {
    list: [
      {
        id: "support",
        tools: { profile: "messaging", allow: ["slack"] }
      }
    ]
  }
}
```

## 提供商特定的工具策略

使用 `tools.byProvider` 来**进一步限制**特定提供商的工具
（或单个 `provider/model`），而不更改全局默认值。
每个智能体覆盖：`agents.list[].tools.byProvider`。

这在基础工具配置文件**之后**和允许/拒绝列表**之前**应用，
因此它只能缩小工具集。
提供商键接受 `provider`（例如 `google-antigravity`）或
`provider/model`（例如 `openai/gpt-5.2`）。

示例（保持全局编码配置文件，但为 Google Antigravity 提供最小工具集）：
```json5
{
  tools: {
    profile: "coding",
    byProvider: {
      "google-antigravity": { profile: "minimal" }
    }
  }
}
```

示例（针对不稳定端点的提供商/模型特定允许列表）：
```json5
{
  tools: {
    allow: ["group:fs", "group:runtime", "sessions_list"],
    byProvider: {
      "openai/gpt-5.2": { allow: ["group:fs", "sessions_list"] }
    }
  }
}
```

示例（单个提供商的智能体特定覆盖）：
```json5
{
  agents: {
    list: [
      {
        id: "support",
        tools: {
          byProvider: {
            "google-antigravity": { allow: ["message", "sessions_list"] }
          }
        }
      }
    ]
  }
}
```

## 工具组（简写）

工具策略（全局、智能体、沙箱）支持 `group:*` 条目，这些条目会展开为多个工具。
在 `tools.allow` / `tools.deny` 中使用这些。

可用组：
- `group:runtime`：`exec`、`bash`、`process`
- `group:fs`：`read`、`write`、`edit`、`apply_patch`
- `group:sessions`：`sessions_list`、`sessions_history`、`sessions_send`、`sessions_spawn`、`session_status`
- `group:memory`：`memory_search`、`memory_get`
- `group:web`：`web_search`、`web_fetch`
- `group:ui`：`browser`、`canvas`
- `group:automation`：`cron`、`gateway`
- `group:messaging`：`message`
- `group:nodes`：`nodes`
- `group:moltbot`：所有内置 Moltbot 工具（不包括提供商插件）

示例（仅允许文件工具 + 浏览器）：
```json5
{
  tools: {
    allow: ["group:fs", "browser"]
  }
}
```

## 插件 + 工具

插件可以注册**额外的工具**（和 CLI 命令），超出核心工具集。
有关安装 + 配置，请参阅 [插件](/plugin)，有关工具使用指南如何注入到提示中，请参阅 [技能](/tools/skills)。一些插件会随工具一起提供自己的技能（例如，voice-call 插件）。

可选插件工具：
- [Lobster](/tools/lobster)：带有可恢复批准的类型化工作流运行时（需要网关节点上的 Lobster CLI）。
- [LLM Task](/tools/llm-task)：仅 JSON 的 LLM 步骤，用于结构化工作流输出（可选模式验证）。

## 工具清单

### `apply_patch`
跨一个或多个文件应用结构化补丁。用于多块编辑。
实验性：通过 `tools.exec.applyPatch.enabled` 启用（仅 OpenAI 模型）。

### `exec`
在工作区中运行 shell 命令。

核心参数：
- `command`（必需）
- `yieldMs`（超时后自动后台运行，默认 10000）
- `background`（立即后台运行）
- `timeout`（秒；如果超过则终止进程，默认 1800）
- `elevated`（布尔值；如果启用/允许提升模式，则在主机上运行；仅当智能体被沙箱化时才更改行为）
- `host`（`sandbox | gateway | node`）
- `security`（`deny | allowlist | full`）
- `ask`（`off | on-miss | always`）
- `node`（`host=node` 的节点 ID/名称）
- 需要真实 TTY？设置 `pty: true`。

注意：
- 后台运行时返回 `status: "running"` 和 `sessionId`。
- 使用 `process` 轮询/日志/写入/终止/清除后台会话。
- 如果 `process` 被拒绝，`exec` 同步运行并忽略 `yieldMs`/`background`。
- `elevated` 由 `tools.elevated` 加上任何 `agents.list[].tools.elevated` 覆盖控制（两者都必须允许），并且是 `host=gateway` + `security=full` 的别名。
- `elevated` 仅当智能体被沙箱化时才更改行为（否则无操作）。
- `host=node` 可以 targeting macOS 配套应用或无头节点主机（`moltbot node run`）。
- 网关/节点批准和允许列表：[Exec 批准](/tools/exec-approvals)。

### `process`
管理后台 exec 会话。

核心操作：
- `list`、`poll`、`log`、`write`、`kill`、`clear`、`remove`

注意：
- `poll` 在完成时返回新输出和退出状态。
- `log` 支持基于行的 `offset`/`limit`（省略 `offset` 以获取最后 N 行）。
- `process` 按智能体作用域；其他智能体的会话不可见。

### `web_search`
使用 Brave Search API 搜索网络。

核心参数：
- `query`（必需）
- `count`（1–10；默认为 `tools.web.search.maxResults`）

注意：
- 需要 Brave API 密钥（推荐：`moltbot configure --section web`，或设置 `BRAVE_API_KEY`）。
- 通过 `tools.web.search.enabled` 启用。
- 响应被缓存（默认 15 分钟）。
- 有关设置，请参阅 [Web 工具](/tools/web)。

### `web_fetch`
从 URL 获取并提取可读内容（HTML → markdown/文本）。

核心参数：
- `url`（必需）
- `extractMode`（`markdown` | `text`）
- `maxChars`（截断长页面）

注意：
- 通过 `tools.web.fetch.enabled` 启用。
- 响应被缓存（默认 15 分钟）。
- 对于 JS 密集型站点，首选浏览器工具。
- 有关设置，请参阅 [Web 工具](/tools/web)。
- 有关可选的反机器人回退，请参阅 [Firecrawl](/tools/firecrawl)。

### `browser`
控制专用的 clawd 浏览器。

核心操作：
- `status`、`start`、`stop`、`tabs`、`open`、`focus`、`close`
- `snapshot`（aria/ai）
- `screenshot`（返回图像块 + `MEDIA:<path>`）
- `act`（UI 操作：click/type/press/hover/drag/select/fill/resize/wait/evaluate）
- `navigate`、`console`、`pdf`、`upload`、`dialog`

配置文件管理：
- `profiles` — 列出所有浏览器配置文件及其状态
- `create-profile` — 创建具有自动分配端口（或 `cdpUrl`）的新配置文件
- `delete-profile` — 停止浏览器，删除用户数据，从配置中移除（仅本地）
- `reset-profile` — 终止配置文件端口上的孤立进程（仅本地）

常见参数：
- `profile`（可选；默认为 `browser.defaultProfile`）
- `target`（`sandbox` | `host` | `node`）
- `node`（可选；选择特定节点 ID/名称）
注意：
- 需要 `browser.enabled=true`（默认值为 `true`；设置 `false` 以禁用）。
- 所有操作都接受可选的 `profile` 参数以支持多实例。
- 当省略 `profile` 时，使用 `browser.defaultProfile`（默认为 "chrome"）。
- 配置文件名称：仅小写字母数字 + 连字符（最多 64 个字符）。
- 端口范围：18800-18899（最多约 100 个配置文件）。
- 远程配置文件仅支持附加（无启动/停止/重置）。
- 如果连接了支持浏览器的节点，工具可能会自动路由到它（除非您固定 `target`）。
- 安装 Playwright 时，`snapshot` 默认使用 `ai`；使用 `aria` 获取可访问性树。
- `snapshot` 还支持角色快照选项（`interactive`、`compact`、`depth`、`selector`），返回类似 `e12` 的引用。
- `act` 需要来自 `snapshot` 的 `ref`（AI 快照中的数字 `12`，或角色快照中的 `e12`）；对于罕见的 CSS 选择器需求，使用 `evaluate`。
- 默认情况下避免 `act` → `wait`；仅在特殊情况下使用（无可靠的 UI 状态可等待）。
- `upload` 可以选择传递 `ref` 以在准备后自动点击。
- `upload` 还支持 `inputRef`（aria 引用）或 `element`（CSS 选择器）直接设置 `<input type="file">`。

### `canvas`
驱动节点画布（呈现、评估、快照、A2UI）。

核心操作：
- `present`、`hide`、`navigate`、`eval`
- `snapshot`（返回图像块 + `MEDIA:<path>`）
- `a2ui_push`、`a2ui_reset`

注意：
- 在底层使用网关 `node.invoke`。
- 如果未提供 `node`，工具会选择默认节点（单个连接节点或本地 mac 节点）。
- A2UI 仅支持 v0.8（无 `createSurface`）；CLI 会拒绝 v0.9 JSONL 并显示行错误。
- 快速测试：`moltbot nodes canvas a2ui push --node <id> --text "Hello from A2UI"`。

### `nodes`
发现并 targeting 配对节点；发送通知；捕获摄像头/屏幕。

核心操作：
- `status`、`describe`
- `pending`、`approve`、`reject`（配对）
- `notify`（macOS `system.notify`）
- `run`（macOS `system.run`）
- `camera_snap`、`camera_clip`、`screen_record`
- `location_get`

注意：
- 摄像头/屏幕命令要求节点应用程序在前台运行。
- 图像返回图像块 + `MEDIA:<path>`。
- 视频返回 `FILE:<path>`（mp4）。
- 位置返回 JSON 负载（lat/lon/accuracy/timestamp）。
- `run` 参数：`command` argv 数组；可选 `cwd`、`env`（`KEY=VAL`）、`commandTimeoutMs`、`invokeTimeoutMs`、`needsScreenRecording`。

示例（`run`）：
```json
{
  "action": "run",
  "node": "office-mac",
  "command": ["echo", "Hello"],
  "env": ["FOO=bar"],
  "commandTimeoutMs": 12000,
  "invokeTimeoutMs": 45000,
  "needsScreenRecording": false
}
```

### `image`
使用配置的图像模型分析图像。

核心参数：
- `image`（必需路径或 URL）
- `prompt`（可选；默认为 "Describe the image."）
- `model`（可选覆盖）
- `maxBytesMb`（可选大小上限）

注意：
- 仅当配置了 `agents.defaults.imageModel`（主模型或回退模型）时可用，或者当可以从默认模型 + 配置的认证中推断出隐式图像模型时（尽力配对）。
- 直接使用图像模型（独立于主聊天模型）。

### `message`
跨 Discord/Google Chat/Slack/Telegram/WhatsApp/Signal/iMessage/MS Teams 发送消息和频道操作。

核心操作：
- `send`（文本 + 可选媒体；MS Teams 还支持 `card` 用于自适应卡片）
- `poll`（WhatsApp/Discord/MS Teams 投票）
- `react` / `reactions` / `read` / `edit` / `delete`
- `pin` / `unpin` / `list-pins`
- `permissions`
- `thread-create` / `thread-list` / `thread-reply`
- `search`
- `sticker`
- `member-info` / `role-info`
- `emoji-list` / `emoji-upload` / `sticker-upload`
- `role-add` / `role-remove`
- `channel-info` / `channel-list`
- `voice-status`
- `event-list` / `event-create`
- `timeout` / `kick` / `ban`

注意：
- `send` 通过网关路由 WhatsApp；其他频道直接发送。
- `poll` 对 WhatsApp 和 MS Teams 使用网关；Discord 投票直接发送。
- 当消息工具调用绑定到活动聊天会话时，发送被限制在该会话的目标上，以避免跨上下文泄漏。

### `cron`
管理网关定时任务和唤醒。

核心操作：
- `status`、`list`
- `add`、`update`、`remove`、`run`、`runs`
- `wake`（入队系统事件 + 可选立即心跳）

注意：
- `add` 需要完整的定时任务对象（与 `cron.add` RPC 相同的架构）。
- `update` 使用 `{ id, patch }`。

### `gateway`
重启或对运行中的网关进程应用更新（就地）。

核心操作：
- `restart`（授权 + 发送 `SIGUSR1` 进行进程内重启；`moltbot gateway` 就地重启）
- `config.get` / `config.schema`
- `config.apply`（验证 + 写入配置 + 重启 + 唤醒）
- `config.patch`（合并部分更新 + 重启 + 唤醒）
- `update.run`（运行更新 + 重启 + 唤醒）

注意：
- 使用 `delayMs`（默认为 2000）以避免中断正在进行的回复。
- `restart` 默认禁用；通过 `commands.restart: true` 启用。

### `sessions_list` / `sessions_history` / `sessions_send` / `sessions_spawn` / `session_status`
列出会话，检查记录历史，或发送到另一个会话。

核心参数：
- `sessions_list`：`kinds?`、`limit?`、`activeMinutes?`、`messageLimit?`（0 = 无）
- `sessions_history`：`sessionKey`（或 `sessionId`）、`limit?`、`includeTools?`
- `sessions_send`：`sessionKey`（或 `sessionId`）、`message`、`timeoutSeconds?`（0 = 即发即忘）
- `sessions_spawn`：`task`、`label?`、`agentId?`、`model?`、`runTimeoutSeconds?`、`cleanup?`
- `session_status`：`sessionKey?`（默认为当前；接受 `sessionId`）、`model?`（`default` 清除覆盖）

注意：
- `main` 是规范的直接聊天键；全局/未知会话被隐藏。
- `messageLimit > 0` 每个会话获取最后 N 条消息（工具消息被过滤）。
- 当 `timeoutSeconds > 0` 时，`sessions_send` 等待最终完成。
- 传递/公告在完成后进行，尽力而为；`status: "ok"` 确认智能体运行完成，而不是公告已传递。
- `sessions_spawn` 启动子智能体运行并向请求者聊天发布公告回复。
- `sessions_spawn` 是非阻塞的，立即返回 `status: "accepted"`。
- `sessions_send` 运行回复-回 ping-pong（回复 `REPLY_SKIP` 停止；最大轮次通过 `session.agentToAgent.maxPingPongTurns`，0–5）。
- ping-pong 后，目标智能体运行**公告步骤**；回复 `ANNOUNCE_SKIP` 以抑制公告。

### `agents_list`
列出当前会话可以使用 `sessions_spawn` 目标的智能体 ID。

注意：
- 结果受每个智能体允许列表的限制（`agents.list[].subagents.allowAgents`）。
- 当配置为 `["*"]` 时，工具包含所有配置的智能体并标记 `allowAny: true`。

## 参数（通用）

网关支持的工具（`canvas`、`nodes`、`cron`）：
- `gatewayUrl`（默认 `ws://127.0.0.1:18789`）
- `gatewayToken`（如果启用了认证）
- `timeoutMs`

浏览器工具：
- `profile`（可选；默认为 `browser.defaultProfile`）
- `target`（`sandbox` | `host` | `node`）
- `node`（可选；固定特定节点 ID/名称）

## 推荐的智能体流程

浏览器自动化：
1) `browser` → `status` / `start`
2) `snapshot`（ai 或 aria）
3) `act`（click/type/press）
4) `screenshot`（如果需要视觉确认）

画布渲染：
1) `canvas` → `present`
2) `a2ui_push`（可选）
3) `snapshot`

节点 targeting：
1) `nodes` → `status`
2) 在选定节点上 `describe`
3) `notify` / `run` / `camera_snap` / `screen_record`

## 安全

- 避免直接 `system.run`；仅在获得明确用户同意后使用 `nodes` → `run`。
- 尊重用户对摄像头/屏幕捕获的同意。
- 在调用媒体命令前使用 `status/describe` 确保权限。

## 工具如何呈现给智能体

工具通过两个并行通道暴露：

1) **系统提示文本**：人类可读的列表 + 指南。
2) **工具模式**：发送到模型 API 的结构化函数定义。

这意味着智能体同时看到"存在什么工具"和"如何调用它们"。如果工具
没有出现在系统提示或模式中，模型就无法调用它。
