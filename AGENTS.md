# 仓库指南
- 仓库: https://github.com/moltbot/moltbot
- GitHub issues/评论/PR 评论: 使用字面量多行字符串或 `-F - <<'EOF'` (或 $'...') 来表示真正的换行符;永远不要嵌入 "\\n"。

## 项目结构与模块组织
- 源代码: `src/` (CLI 连线在 `src/cli`, 命令在 `src/commands`, Web 提供者在 `src/provider-web.ts`, 基础设施在 `src/infra`, 媒体管道在 `src/media`)。
- 测试: 共置的 `*.test.ts`。
- 文档: `docs/` (图片、队列、Pi 配置)。构建输出位于 `dist/`。
- 插件/扩展: 位于 `extensions/*` 下(工作区包)。将仅插件的依赖项保留在扩展的 `package.json` 中;除非核心使用它们,否则不要将它们添加到根 `package.json` 中。
- 插件: 安装在插件目录中运行 `npm install --omit=dev`;运行时依赖项必须位于 `dependencies` 中。避免在 `dependencies` 中使用 `workspace:*`(npm install 会中断);将 `moltbot` 放在 `devDependencies` 或 `peerDependencies` 中(运行时通过 jiti 别名解析 `clawdbot/plugin-sdk`)。
- 从 `https://molt.bot/*` 提供的安装程序: 位于同级仓库 `../molt.bot` 中 (`public/install.sh`, `public/install-cli.sh`, `public/install.ps1`)。
- 消息频道: 在重构共享逻辑时,始终考虑**所有**内置 + 扩展频道(路由、允许列表、配对、命令门控、引导、文档)。
  - 核心频道文档: `docs/channels/`
  - 核心频道代码: `src/telegram`, `src/discord`, `src/slack`, `src/signal`, `src/imessage`, `src/web` (WhatsApp web), `src/channels`, `src/routing`
  - 扩展(频道插件): `extensions/*` (例如 `extensions/msteams`, `extensions/matrix`, `extensions/zalo`, `extensions/zalouser`, `extensions/voice-call`)
- 添加频道/扩展/应用/文档时,查看 `.github/labeler.yml` 以了解标签覆盖范围。

## 文档链接(Mintlify)
- 文档托管在 Mintlify 上(docs.molt.bot)。
- `docs/**/*.md` 中的内部文档链接: 根相对路径,不带 `.md`/`.mdx`(示例: `[Config](/configuration)`)。
- 章节交叉引用: 在根相对路径上使用锚点(示例: `[Hooks](/configuration#hooks)`)。
- 文档标题和锚点: 避免在标题中使用破折号和撇号,因为它们会破坏 Mintlify 锚点链接。
- 当 Peter 要求提供链接时,回复完整的 `https://docs.molt.bot/...` URL(而不是根相对路径)。
- 当您接触文档时,在回复末尾附上您引用的 `https://docs.molt.bot/...` URL。
- README (GitHub): 保留绝对文档 URL (`https://docs.molt.bot/...`),以便链接在 GitHub 上正常工作。
- 文档内容必须是通用的:没有个人设备名称/主机名/路径;使用占位符如 `user@gateway-host` 和 "gateway host"。

## exe.dev VM 运维(常规)
- 访问: 稳定路径是 `ssh exe.dev` 然后 `ssh vm-name`(假设 SSH 密钥已设置)。
- SSH 不稳定: 使用 exe.dev Web 终端或 Shelley(Web 代理);为长时间操作保留一个 tmux 会话。
- 更新: `sudo npm i -g moltbot@latest`(全局安装需要 `/usr/lib/node_modules` 上的 root 权限)。
- 配置: 使用 `moltbot config set ...`;确保设置了 `gateway.mode=local`。
- Discord: 仅存储原始令牌(不带 `DISCORD_BOT_TOKEN=` 前缀)。
- 重启: 停止旧的网关并运行:
  `pkill -9 -f moltbot-gateway || true; nohup moltbot gateway run --bind loopback --port 18789 --force > /tmp/moltbot-gateway.log 2>&1 &`
- 验证: `moltbot channels status --probe`, `ss -ltnp | rg 18789`, `tail -n 120 /tmp/moltbot-gateway.log`。

## 构建、测试和开发命令
- 运行时基线: Node **22+**(保持 Node + Bun 路径正常工作)。
- 安装依赖项: `pnpm install`
- 提交前钩子: `prek install`(运行与 CI 相同的检查)
- 也支持: `bun install`(在接触依赖项/补丁时保持 `pnpm-lock.yaml` + Bun 补丁同步)。
- 优先使用 Bun 进行 TypeScript 执行(脚本、开发、测试): `bun <file.ts>` / `bunx <tool>`。
- 在开发中运行 CLI: `pnpm moltbot ...`(bun) 或 `pnpm dev`。
- Node 仍支持运行构建的输出(`dist/*`)和生产安装。
- Mac 打包(开发): `scripts/package-mac-app.sh` 默认为当前架构。发布检查清单: `docs/platforms/mac/release.md`。
- 类型检查/构建: `pnpm build`(tsc)
- Lint/格式化: `pnpm lint`(oxlint), `pnpm format`(oxfmt)
- 测试: `pnpm test`(vitest);覆盖率: `pnpm test:coverage`

## 编码风格和命名约定
- 语言: TypeScript (ESM)。优先使用严格类型;避免 `any`。
- 通过 Oxlint 和 Oxfmt 进行格式化/linting;在提交之前运行 `pnpm lint`。
- 为棘手或非显而易见的逻辑添加简短的代码注释。
- 保持文件简洁;提取辅助函数而不是 "V2" 副本。为 CLI 选项和通过 `createDefaultDeps` 的依赖注入使用现有模式。
- 目标是将文件保持在约 700 LOC 以下;这只是一个指导原则(不是硬性护栏)。在提高清晰度或可测试性时进行拆分/重构。
- 命名: 使用 **Moltbot** 作为产品/应用/文档标题;使用 `moltbot` 作为 CLI 命令、包/二进制文件、路径和配置键。

## 发布频道(命名)
- stable: 仅标记的发布版本(例如 `vYYYY.M.D`),npm dist-tag `latest`。
- beta: 预发布标签 `vYYYY.M.D-beta.N`,npm dist-tag `beta`(可能在没有 macOS 应用的情况下发布)。
- dev: 在 `main` 上移动的头部(没有标签;git checkout main)。

## 测试指南
- 框架: Vitest,具有 V8 覆盖率阈值(70% 行/分支/函数/语句)。
- 命名: 将源名称与 `*.test.ts` 匹配;e2e 在 `*.e2e.test.ts` 中。
- 当您接触逻辑时,在推送之前运行 `pnpm test`(或 `pnpm test:coverage`)。
- 不要将测试工作线程设置在 16 以上;已经尝试过了。
- 实时测试(真实密钥): `CLAWDBOT_LIVE_TEST=1 pnpm test:live`(仅 Moltbot)或 `LIVE=1 pnpm test:live`(包括提供者实时测试)。Docker: `pnpm test:docker:live-models`, `pnpm test:docker:live-gateway`。引导 Docker E2E: `pnpm test:docker:onboard`。
- 完整工具包 + 覆盖内容: `docs/testing.md`。
- 纯测试添加/修复通常**不**需要更改日志条目,除非它们改变了面向用户的行为或用户要求。

## 提交和拉取请求指南
- 使用 `scripts/committer "<msg>" <file...>` 创建提交;避免手动 `git add`/`git commit`,以便暂存保持范围限定。
- 遵循简洁、以行动为导向的提交消息(例如,`CLI: add verbose flag to send`)。
- 对相关更改进行分组;避免捆绑不相关的重构。
- 更改日志工作流: 将最新发布的版本保留在顶部(没有 `Unreleased`);发布后,增加版本并开始新的顶部部分。
- PR 应该总结范围,注意执行的测试,并提及任何面向用户的更改或新标志。
- PR 审查流程: 当给出 PR 链接时,通过 `gh pr view`/`gh pr diff` 审查,并且**不要**更改分支。
- PR 审查调用: 优先使用单个 `gh pr view --json ...` 来批量处理元数据/评论;仅在需要时运行 `gh pr diff`。
- 在粘贴 GH Issue/PR 时开始审查之前: 运行 `git pull`;如果有本地更改或未推送的提交,请在审查之前停止并提醒用户。
- 目标: 合并 PR。当提交干净时优先使用 **rebase**;当历史记录混乱时使用 **squash**。
- PR 合并流程: 从 `main` 创建一个临时分支,将 PR 分支合并到其中(除非提交历史记录很重要,否则优先使用 squash;当重要时使用 rebase/merge)。始终尝试合并 PR,除非真的困难,然后使用另一种方法。如果我们 squash,将 PR 作者添加为共同贡献者。应用修复,添加更改日志条目(包括 PR # + 感谢),在最终提交之前运行完整关卡,提交,合并回 `main`,删除临时分支,并在 `main` 上结束。
- 如果您审查 PR 并稍后对其进行工作,则通过 merge/squash 登陆(没有直接主提交),并且始终将 PR 作者添加为共同贡献者。
- 处理 PR 时: 添加带有 PR 号的更改日志条目并感谢贡献者。
- 处理 issue 时: 在更改日志条目中引用该 issue。
- 合并 PR 时: 留下一条 PR 评论,准确解释我们所做的工作并包括 SHA 哈希。
- 从新贡献者合并 PR 时: 将他们的头像添加到 README "Thanks to all clawtributors" 缩略图列表中。
- 合并 PR 后: 如果缺少贡献者,则运行 `bun scripts/update-clawtributors.ts`,然后提交重新生成的 README。

## 简写命令
- `sync`: 如果工作树是脏的,则提交所有更改(选择一个合理的 Conventional Commit 消息),然后 `git pull --rebase`;如果 rebase 冲突且无法解决,则停止;否则 `git push`。

### PR 工作流程(审查 vs 登陆)
- **审查模式(仅 PR 链接):** 阅读 `gh pr view/diff`;**不要**切换分支;**不要**更改代码。
- **登陆模式:** 从 `main` 创建一个集成分支,引入 PR 提交(对于线性历史记录**优先使用 rebase**;当复杂性/冲突使其更安全时**允许合并**),应用修复,添加更改日志(+ 感谢 + PR #),在提交之前**本地运行完整关卡**(`pnpm lint && pnpm build && pnpm test`),提交,合并回 `main`,然后 `git switch main`(登陆后永远不要停留在主题分支上)。重要: 贡献者需要在此之后的 git 图中!
- **多智能体安全:** 除非明确要求,否则**不要**创建/应用/删除 `git stash` 条目(这包括 `git pull --rebase --autostash`)。假设其他智能体可能正在工作;保持不相关的 WIP 不受影响,避免跨领域的状态更改。
- **多智能体安全:** 当用户说 "push" 时,您可以 `git pull --rebase` 来集成最新的更改(永远不要丢弃其他智能体的工作)。当用户说 "commit" 时,范围仅限于您的更改。当用户说 "commit all" 时,将所有内容分组提交。
- **多智能体安全:** 除非明确要求,否则**不要**创建/删除/修改 `git worktree` 检出(或编辑 `.worktrees/*`)。
- **多智能体安全:** 除非明确要求,否则**不要**切换分支/签出不同的分支。
- **多智能体安全:** 只要每个智能体都有自己的会话,运行多个智能体是可以的。
- **多智能体安全:** 当您看到无法识别的文件时,继续进行;专注于您的更改并仅提交这些更改。
- Lint/格式化波动:
  - 如果暂存+未暂存的差异仅是格式化,则自动解决而无需询问。
  - 如果已经请求提交/推送,则自动暂存并将仅格式化的后续内容包含在同一提交中(如果需要,则在一个微小的后续提交中),无需额外确认。
  - 仅当更改是语义性的(逻辑/数据/行为)时才询问。
- 龙虾接缝: 使用 `src/terminal/palette.ts` 中的共享 CLI 调色板(没有硬编码颜色);根据需要将调色板应用于引导/配置提示和其他 TTY UI 输出。
- **多智能体安全:** 专注于您的编辑的报告;避免护栏免责声明,除非真正被阻止;当多个智能体接触同一文件时,如果安全则继续;仅在相关时以简短的 "其他文件存在" 说明结束。
- Bug 调查: 在得出结论之前阅读相关 npm 依赖项的源代码和所有相关本地代码;以高置信度的根本原因为目标。
- 代码风格: 为棘手的逻辑添加简短的注释;在可行的情况下将文件保持在约 500 LOC 以下(根据需要进行拆分/重构)。
- 工具模式护栏(google-antigravity): 避免在工具输入模式中使用 `Type.Union`;没有 `anyOf`/`oneOf`/`allOf`。使用 `stringEnum`/`optionalStringEnum`(Type.Unsafe enum) 作为字符串列表,并使用 `Type.Optional(...)` 代替 `... | null`。将顶级工具模式保持为带有 `properties` 的 `type: "object"`。
- 工具模式护栏: 避免在工具模式中使用原始 `format` 属性名称;某些验证器将 `format` 视为保留关键字并拒绝该模式。
- 当被要求打开 "session" 文件时,打开 `~/.clawdbot/agents/<agentId>/sessions/*.jsonl` 下的 Pi 会话日志(使用系统提示的 Runtime 行中的 `agent=<id>` 值;除非给出特定 ID,否则使用最新的),而不是默认的 `sessions.json`。如果需要来自另一台机器的日志,请通过 Tailscale SSH 并在那里读取相同路径。
- 不要通过 SSH 重建 macOS 应用;重建必须直接在 Mac 上运行。
- 永远不要向外部消息传递表面(WhatsApp、Telegram)发送流式/部分回复;只有最终回复应该在那里传递。流式/工具事件可能仍会进入内部 UI/控制频道。
- 语音唤醒转发提示:
  - 命令模板应保持 `moltbot-mac agent --message "${text}" --thinking low`;`VoiceWakeForwarder` 已经对 `${text}` 进行了 shell 转义。不要添加额外的引号。
  - launchd PATH 是最小的;确保应用的 launch agent PATH 包括标准系统路径加上您的 pnpm bin(通常是 `$HOME/Library/pnpm`),以便当通过 `moltbot-mac` 调用时 `pnpm`/`moltbot` 二进制文件可以解析。
- 对于包含 `!` 的手动 `moltbot message send` 消息,使用下面提到的 heredoc 模式以避免 Bash 工具的转义。
- 发布护栏: 未经操作员的明确同意,不要更改版本号;在运行任何 npm publish/发布步骤之前始终请求许可。

## NPM + 1Password(发布/验证)
- 使用 1password 技能;所有 `op` 命令必须在新的 tmux 会话中运行。
- 登录: `eval "$(op signin --account my.1password.com)"`(应用已解锁 + 集成已开启)。
- OTP: `op read 'op://Private/Npmjs/one-time password?attribute=otp'`。
- 发布: `npm publish --access public --otp="<otp>"`(从包目录运行)。
- 在没有本地 npmrc 副作用的情况下验证: `npm view <pkg> version --userconfig "$(mktemp)"`。
- 发布后终止 tmux 会话。
