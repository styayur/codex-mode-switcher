# Codex Mode Switcher 中文说明

Windows 上的 PowerShell **Codex Desktop Controller**。通过备份、校验和恢复
`config.toml` 与 Provider 状态，在 ChatGPT OAuth 和一个已保存的自定义 API Provider
之间切换，并可显式启动 Desktop。v0.2.1 增加 Windows 原生集成；真实 Desktop Provider 端到端行为仍未验证。

[English README](../README.md) · [故障恢复](TROUBLESHOOTING.md) · [验证记录](DESKTOP-VALIDATION.md)

## 快速开始

需要 Windows、PowerShell 7.4+；启动功能需要安装 Desktop。无需管理员权限、Codex CLI、
后台服务或 API 网关。本项目不提供 GUI，不是 CLI Profile Switcher，也非 OpenAI 或 DeepSeek 官方项目。

请保留整个仓库，入口脚本依赖 `src/`。审查下载文件后，若遇到 MOTW，可以执行：

```powershell
Get-ChildItem . -Recurse -File -Include *.ps1,*.psm1,*.psd1,*.cs | Unblock-File
```

脚本不更改 ExecutionPolicy，也不绕过组织策略。先准备已验证可用的自定义 Provider 配置，
正常结束或停止相关任务并退出 Desktop，再执行：

```powershell
.\codex-mode.ps1 Diagnose -Json
.\codex-mode.ps1 Init
.\codex-mode.ps1 GPT -Launch
# 完成任务并再次退出 Desktop 后：
.\codex-mode.ps1 DeepSeek -Launch
```

`DeepSeek` 是兼容旧版的命令名称，恢复的是你保存的唯一自定义 Provider，不限于 DeepSeek。
工具不会创建 API 账号、选择第三方模型或转换协议。

## 使用

| 命令或参数 | 用途 |
| --- | --- |
| `Status` / `Diagnose` | 只读诊断配置、应用身份、运行状态、备份和恢复状态。 |
| `Init` | 备份现有配置并保存当前自定义 Provider；GPT 模式下保留已存状态。 |
| `GPT` | 保存自定义 Provider，选择 OpenAI/ChatGPT，保留或恢复原生模型与推理设置。 |
| `DeepSeek` | 保存原生 GPT 选择，恢复已保存的自定义 Provider。 |
| `Toggle` | 在两种选择之间切换。 |
| `-Launch` | 配置事务成功后启动 Desktop，仅适用于 GPT/DeepSeek/Toggle。 |
| `-WaitForExit` | 交互确认后有界等待用户正常退出，不强制关闭。 |
| `-DryRun` | 预览计划，不写文件、不加锁、不提问、不启动应用。 |
| `-NonInteractive -TasksStopped` | 用户明确确认任务已停止；Desktop 仍在运行时依然拒绝切换。 |
| `Recover -TransactionId <id>` | 对未提交事务，在哈希和备份匹配时恢复原始文件。 |

```powershell
.\codex-mode.ps1 GPT -Launch -DryRun -Json
.\codex-mode.ps1 GPT -Launch -WaitForExit -ExitTimeoutSeconds 60
.\codex-mode.ps1 GPT -Launch -NonInteractive -TasksStopped
```

不加 `-Launch` 只修改配置，但仍拒绝在 Desktop 运行中或身份不明时写入。工具依据系统安装身份
和可执行文件路径识别应用，不把名称相似的 `codex.exe` 当成 Desktop。

`-Json` 输出结构化结果，`-PassThru` 返回对象；失败仍抛出脱敏错误。
`Committed` 表示配置是否提交。`LaunchVerified` 只表示观察到身份匹配的进程，
`ProviderLoaded` 始终为 `NotVerified`，不能据此断言新 Provider 已载入。
进程不存在也不能证明任务已全部完成。请重启后使用新任务验证模型和 Provider。

## v0.2.1 模块与 Windows 集成

源码目录中执行 `Import-Module .\CodexModeSwitcher.psd1`；把 Release 模块包解压到当前用户
PowerShell 模块目录后，可直接按名称导入。详见 [Windows Integration](WINDOWS-INTEGRATION.md)。

```powershell
Import-Module CodexModeSwitcher
Get-CodexStatus
Test-CodexEnvironment
Start-CodexMode GPT -DryRun
Start-CodexMode GPT
Start-CodexMode DeepSeek
```

`Start-CodexMode` 默认安全切换后启动 Desktop，`-ConfigurationOnly` 仅切换配置。
支持 `-WhatIf`、`-DryRun` 及原有等待/非交互安全参数。模块函数返回结构化结果，自动化调用者
应检查 `State`；脚本和 cmd 入口还会通过非零退出码报告失败。导入模块不会安装集成或启动应用。

```powershell
codex-mode install terminal          # 默认预览，不写文件
codex-mode install terminal -Apply   # 审查预览后显式应用
codex-mode install startmenu -Apply
codex-mode integration list
codex-mode uninstall terminal -Apply
codex-mode integration uninstall-all -Apply
```

Terminal 使用独立 JSON fragment，添加 Codex GPT、Codex DeepSeek、Codex Diagnose，
不改写已有 settings.json。开始菜单集成创建同名原生快捷方式；默认不安装，不创建桌面快捷方式，
不注册右键菜单。卸载默认也预览，添加 `-Apply` 才执行；仅删除有所有权记录且哈希匹配的文件，
用户改动与无关文件会保留。备份、所有权记录和空目录保留用于审计恢复。

```powershell
codex-mode install notifications -Apply
Start-CodexMode GPT -Notify
codex-mode uninstall notifications -Apply
```

通知另行启用，会创建专用的开始菜单身份快捷方式；没有后台服务。
每次还需显式 `-Notify`。通知只含固定状态文字，发送失败或被 Windows 屏蔽都不影响核心结果。
诊断和预览不会发通知。原有 Profile 快捷函数由旧安装器单独卸载，不纳入新的三类集成管理。

项目不管理认证，不修改会话数据库，不提供模型网关，不运行后台服务，也不替代 Codex 官方配置。

## 认证、数据与兼容性

**ChatGPT OAuth ≠ OpenAI API Key**。ChatGPT 订阅权益与第三方 API 计费不同。
Codex 可保留 ChatGPT 登录，同时选择自定义 Provider。密钥通过适当的环境变量或凭据管理器
提供，不能提交到仓库；MSIX 应用不一定继承当前 PowerShell 的环境。

控制器不读取、复制或修改 `auth.json`、会话或数据库，不调用 CLI login/doctor。
旧参数 `-NoLogin`、`-SkipDoctor` 仍接受，但已无副作用。首次从自定义 Provider 切到 GPT 且
没有原生状态时，采用 Codex/账号默认模型；之后可保存并恢复原生模型选择。
MCP、sandbox、projects 等无关配置保留。旧版有效 Provider 状态文件仍兼容。

默认配置目录是 `$HOME/.codex`，也可指定绝对路径 `$env:CODEX_HOME`。
MSIX 的自定义 home 启动继承机制尚未验证，因此 `-Launch` 仅允许默认 home 且持久环境不冲突。
Win32 启动显式传递 home，其实际消费行为仍需端到端验收。

## 可选快捷命令

```powershell
.\scripts\Install-DesktopShortcut.ps1 -DryRun
.\scripts\Install-DesktopShortcut.ps1
# 新 PowerShell 会话中：
cdx-gpt
cdx-deepseek -WaitForExit
.\scripts\Install-DesktopShortcut.ps1 -Action Uninstall
```

安装器显式修改当前用户的 PowerShell Profile，先备份，拒绝覆盖已有函数或别名；卸载仅移除
未经用户改动的自有块。启动 PowerShell 时只定义函数，不执行 Codex 检查。

## 安全与限制

配置修改前先备份；单文件原子替换，多文件通过事务日志恢复。提交前失败仅在当前哈希仍符合
记录时回滚；提交后启动失败不自动覆盖配置。检测到外部修改会保留新内容并停止。
工具锁只协调自身调用，无法完全排除外部程序在最终检查后的竞态。

备份可能含原配置已有的内嵌密钥和私人路径，必须保留在私有目录，不能发到 Issue。
诊断包含本地路径，分享前需脱敏。工具不自动删除备份，不杀进程，不取消任务。

不保证运行中的 Desktop 热重载，也不保证旧会话跨 Provider 无缝继续。
第三方协议兼容性由对应服务决定。本版本不读取内部会话数据库、不调用未公开控制接口。
仅编辑用户级配置，活动根 profile 会阻止启动，其他覆盖来源不做完整解析。
保守 TOML 编辑器拒绝多行值、引号/数组形式的受管 Provider 表等不支持语法。

完整测试命令为 `pwsh -NoProfile -File ./scripts/Test-Project.ps1`。
自动化使用隔离 home 和模拟启动器，不会启动或关闭真实 Desktop。
真实发现验证、模拟测试和发布前手工验收分别列在[验证记录](DESKTOP-VALIDATION.md)。

许可证为 [MIT](../LICENSE)。安全问题请按 [SECURITY.md](../SECURITY.md) 私下报告。
