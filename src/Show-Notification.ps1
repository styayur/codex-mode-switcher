# Windows PowerShell 5.1 WinRT bridge. No user/config values accepted.
[CmdletBinding()]
param([ValidateSet('GPT','DeepSeek','Completed','Failed','DesktopRunning','CommittedLaunchFailed')][string]$Outcome)
$ErrorActionPreference='Stop'
try {
    $messages=@{
        GPT='Switched to GPT. Verify provider/model in a new Desktop task. Desktop restart may be required.'
        DeepSeek='Switched to the saved provider (DeepSeek command). Desktop restart may be required.'
        Completed='Operation completed. Check local diagnostics for details.'
        Failed='Switch failed. Review local diagnostics.'
        DesktopRunning='Switch failed. Reason: Desktop still running. Finish tasks and exit normally.'
        CommittedLaunchFailed='Configuration committed, but Desktop launch failed. No automatic rollback.'
    }
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
    $xml=New-Object Windows.Data.Xml.Dom.XmlDocument
    $body=[Security.SecurityElement]::Escape($messages[$Outcome])
    $xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>Codex Mode Switcher</text><text>' + $body + '</text></binding></visual></toast>')
    $toast=[Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('styayur.CodexModeSwitcher').Show($toast)
} catch { exit 1 }
