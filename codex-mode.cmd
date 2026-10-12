@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0scripts\Invoke-Command.ps1" %*
exit /b %errorlevel%
