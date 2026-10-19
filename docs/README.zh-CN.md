# Codex Mode Switcher 中文说明

在 Codex Desktop 的 GPT 与一个已保存的自定义 Provider 配置之间切换，提供预览、事务备份和有条件恢复。Windows 原生集成按需启用。

**PowerShell 原生 · CLI 优先 · 只读优先 · 可撤销操作 · 最少依赖**

[English README](../README.md) · [命令参考](USAGE.md) · [故障与恢复](TROUBLESHOOTING.md)

适合已经有可用自定义 Provider、希望减少手工修改 `config.toml` 的用户。独立社区项目，非 OpenAI 或 DeepSeek 官方工具。**真实 Desktop Provider 端到端行为仍未验证**；观察到进程不代表配置或模型已加载。

## 快速开始

需要 Windows、PowerShell 7.4+，以普通用户运行，无需管理员权限或 Codex CLI。请下载完整的 `CodexModeSwitcher-<version>.zip` Release 压缩包，核对 `SHA256SUMS.txt`，解压后安装：

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Install
& "$env:LOCALAPPDATA\Programs\CodexModeSwitcher\codex-mode.ps1" Diagnose -Json
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Verify
```

安装器把入口脚本和完整模块部署到 `%LOCALAPPDATA%\Programs\CodexModeSwitcher`，不把
`CODEX_HOME` 当作程序目录，也不会改动已有配置、认证、会话、状态或备份。v0.1.0/v0.2.0
单文件版本会先备份，再生成转发入口。**不要只下载 `codex-mode.ps1`。** 详见[安装、更新与卸载](INSTALL.md)。

诊断不写配置或启动应用；预览不写文件、不加锁、不提问。输出包含本地路径，分享前需脱敏。应用运行中或配置不受支持时，预览可能无法继续。下载被阻止时参见[校验和 MOTW 说明](WINDOWS-INTEGRATION.md)，不要修改执行策略或绕过组织签名要求。

## 保存与切换

先准备已验证可用的自定义 Provider。**完成或停止相关任务、正常退出 Desktop，并关闭配置编辑器**，再执行：

```powershell
./codex-mode.ps1 Init -DryRun
./codex-mode.ps1 Init
./codex-mode.ps1 GPT -DryRun
./codex-mode.ps1 GPT
./codex-mode.ps1 Status
# 应用关闭时切回已保存的自定义 Provider：
./codex-mode.ps1 DeepSeek -DryRun
./codex-mode.ps1 DeepSeek
```

`DeepSeek` 是旧版兼容命令名，恢复的是保存的唯一自定义 Provider，不限于 DeepSeek。脚本默认只改配置；GPT/DeepSeek/Toggle 可加 `-Launch` 显式启动。不会强制关闭应用；任务完成需要用户确认。请在新 Desktop 任务中验证 Provider 和模型。

## 可选 Windows 集成

```powershell
Import-Module ./CodexModeSwitcher.psd1
Start-CodexMode GPT -DryRun
codex-mode install terminal
codex-mode integration list
codex-mode integration uninstall-all
```

安装/卸载默认预览，显式加 `-Apply` 才写入。模块导入不会安装或启动任何东西。**`Start-CodexMode` 默认会启动 Desktop**，可用 `-ConfigurationOnly` 仅改配置。Terminal、开始菜单及通知都可选；无默认桌面快捷方式、右键菜单或后台服务。详见[集成、校验与卸载](WINDOWS-INTEGRATION.md)。旧 Profile 快捷函数需用原安装器单独卸载。

## 安全和恢复边界

- Desktop 运行中或身份不明时拒绝写入；没有自动任务完成检测。
- 未提交事务仅在日志、备份及当前哈希匹配时恢复。`Recover` 不是成功切换后的通用撤销；已提交后启动失败保留选择，可再次选择 GPT/已存 Provider。
- 单文件原子替换，多文件依赖恢复日志；外部编辑器不受工具锁控制。
- 备份可能含配置中已有的秘密，须私下保存。工具不管理登录、认证或会话数据库，不提供 API 协议转换，不改变权限与计费。
- 只修改受支持的用户级 TOML；多行值、引号形式的受管键/表等会被拒绝。其他配置覆盖可能影响结果。
- MSIX 自定义 home 启动被阻止；Win32 home 消费、真实集成 UI 与 Provider 推理尚需手工验收。不承诺热重载或旧会话无缝迁移。
- 卸载集成不会还原配置、删除备份或撤销密钥；移动目录前先卸载集成，详见卸载文档。

## 文档与贡献

[命令与兼容性](USAGE.md) · [恢复](TROUBLESHOOTING.md) · [架构](architecture/README.md) · [验证记录](DESKTOP-VALIDATION.md) · [版本记录](../CHANGELOG.md)

[MIT](../LICENSE) · [贡献与测试](../CONTRIBUTING.md) · [安全报告](../SECURITY.md)
