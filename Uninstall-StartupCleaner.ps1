# Uninstall Windows Startup Cleaner for current user.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$installDir = Join-Path $env:LOCALAPPDATA 'WindowsStartupCleaner'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) '开机启动项清理工具.lnk'

try {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    if (Test-Path -LiteralPath $installDir) { Remove-Item -LiteralPath $installDir -Recurse -Force }
    [System.Windows.Forms.MessageBox]::Show('卸载完成。', '卸载完成', 'OK', 'Information') | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show("卸载失败：$($_.Exception.Message)", '卸载失败', 'OK', 'Error') | Out-Null
    exit 1
}
