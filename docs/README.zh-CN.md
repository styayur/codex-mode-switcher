# Codex Mode Switcher 中文说明

用于在 **ChatGPT OAuth / Codex 套餐用量**与**一个已保存的自定义 API Provider**之间切换。
项目独立开发，并非 OpenAI 或 DeepSeek 官方项目。完整说明见 [英文 README](../README.md)。

## 快速开始

需要 Windows、PowerShell 7.4+。登录和诊断需要 PATH 中有 Codex CLI。无需管理员权限。
先准备一个已经能正常工作的 DeepSeek 或其他自定义 Provider 配置。

下载并审查脚本后，如果 Windows 因 MOTW（互联网来源标记）阻止执行，可运行：

```powershell
Unblock-File .\codex-mode.ps1
.\codex-mode.ps1 Init
.\codex-mode.ps1 Status
.\codex-mode.ps1 GPT
.\codex-mode.ps1 DeepSeek
.\codex-mode.ps1 Toggle
```

脚本不会修改 ExecutionPolicy；Unblock-File 不会绕过组织策略或 AllSigned 要求。
切换前关闭正在运行的 Codex 任务和配置编辑器，切换后重新启动 CLI 或客户端。

## 命令

| 命令 | 作用 |
| --- | --- |
| `Status`（默认） | 查看 Provider、模型、登录规则、状态文件是否存在；不写入本地文件。 |
| `Init` | 备份配置并保存当前自定义 Provider；OpenAI 模式下不会覆盖已保存状态。 |
| `GPT` | 保存当前自定义配置，选择 openai 和 chatgpt 登录；模型使用 Codex/账号默认值。 |
| `DeepSeek` | 校验并恢复已保存 Provider、模型、目录和端点；名称兼容原脚本，可恢复其他 Provider。 |
| `Toggle` | OpenAI/默认模式切回保存的 Provider；自定义 Provider 切到 GPT。 |

```powershell
# 只修改本地配置，不检查登录，不启动浏览器，不运行 doctor
.\codex-mode.ps1 GPT -NoLogin -SkipDoctor

# 当前终端使用另一套 Codex 配置目录
$env:CODEX_HOME = Join-Path $HOME 'codex-alternate'
.\codex-mode.ps1 Status -NoLogin
```

默认目录为 `$HOME/.codex`，优先采用 `$env:CODEX_HOME`。状态保存在
`mode-switcher/deepseek-state.json`，配置与旧状态备份位于 `mode-switcher/backups/`。
每次修改现有配置前都会备份；重复 GPT/DeepSeek 不会累积配置段或管理注释。
重复 Init 会刷新自定义状态并保留备份。工具只保存一个自定义 Provider。

## 认证与安全

**ChatGPT OAuth ≠ OpenAI API Key。** ChatGPT 登录使用符合条件的套餐权益；API Key
使用相应 Provider 的 API 计费。选择 DeepSeek 并不意味着必须退出 ChatGPT：登录凭据可以保留，
当前请求由 Provider 配置决定。`env_key` 配合 `requires_openai_auth = false` 使用环境变量密钥；
`requires_openai_auth = true` 会使用 OpenAI 认证并忽略 `env_key`。

工具自身不读取、复制或删除 `auth.json`、token、数据库或 sessions。可选的 `codex login`
由 Codex 管理登录存储。`Status` 和登录检查不能证明实际推理请求一定成功。
`-NoLogin` 跳过所有登录命令；GPT 默认会检查 ChatGPT 登录并按需启动登录。
CLI 未提供 doctor 时跳过诊断。登录失败时配置已保存，可选择备份恢复。

API Key 不应写进仓库。请先将配置中的密钥、Authorization 静态头迁移到环境变量。
本地完整配置备份可能含私密路径或配置中的密钥，状态文件也会保存 Provider 原始片段，
不要提交或粘贴到公开 Issue。`.gitignore` 不能替代人工审查。

## 恢复与限制

保存状态缺失、损坏、字段不一致或包含无关表时，恢复失败且不改配置。配置文件缺失但状态有效时，
可恢复 Provider 选择，但无法恢复已丢失的 MCP 等设置；完整恢复需要选取并审查配置备份。
GPT 模式期间新增的无关 MCP、sandbox、projects 设置会在恢复后保留。

脚本是保守的逐行编辑器，不是完整 TOML 解析器：管理键、Provider 表使用普通裸名称和单行值；
多行 TOML、带引号的 Provider 表名、Provider 数组表会拒绝修改。只修改用户级配置，
项目、profile、托管策略及 CLI 参数可能覆盖它；已运行会话也可能保留旧设置。

它恢复已工作的 DeepSeek 配置，不安装协议适配器，也不保证直接连接 DeepSeek。
当前 Codex 文档要求 Responses 协议，具体兼容性取决于 CLI 版本和端点。
Windows PowerShell 5.1 不支持；脚本未签名；备份不会自动删除。

原始验证资料确认过自定义 Provider 与 ChatGPT 登录共存、Init、GPT 切换及 GPT 网络诊断。
这些历史结果不是对所有版本和账号的兼容性承诺。当前回归测试使用临时目录和合成数据，
不发送真实 API 请求。见 [CHANGELOG](../CHANGELOG.md)、[安全说明](../SECURITY.md) 和 [贡献说明](../CONTRIBUTING.md)。

## 架构与核验

[主 README 架构图](../README.md#architecture)和[源码核验记录](architecture/README.md)区分配置切换、已保存 Provider 恢复、手动备份回滚与可选 Codex 子进程；图表只维护一份。
