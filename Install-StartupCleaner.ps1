# Install Windows Startup Cleaner for current user.
# Run via Install-StartupCleaner.bat.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

$sourceDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$installDir = Join-Path $env:LOCALAPPDATA 'WindowsStartupCleaner'
$desktopDir = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopDir '开机启动项清理工具.lnk'

try {
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Path $installDir | Out-Null
    }

    $files = @(
        'StartupCleaner.ps1',
        'StartupCleaner-GUI.ps1',
        'Launch-StartupCleaner-GUI.bat',
        'Uninstall-StartupCleaner.ps1',
        'Uninstall-StartupCleaner.bat',
        'README.md'
    )

    foreach ($file in $files) {
        $source = Join-Path $sourceDir $file
        if (-not (Test-Path -LiteralPath $source)) { throw "缺少安装文件：$file" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $installDir $file) -Force
    }

    $launcher = Join-Path $installDir 'Launch-StartupCleaner-GUI.bat'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcher
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = 'Windows 开机启动项清理工具'
    $shortcut.Save()

    $message = "安装完成！`n`n桌面已创建快捷方式：开机启动项清理工具`n`n如果禁用启动项时提示权限不足，请右键快捷方式选择以管理员身份运行。"
    [System.Windows.Forms.MessageBox]::Show($message, '安装完成', 'OK', 'Information') | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show("安装失败：$($_.Exception.Message)", '安装失败', 'OK', 'Error') | Out-Null
    exit 1
}
