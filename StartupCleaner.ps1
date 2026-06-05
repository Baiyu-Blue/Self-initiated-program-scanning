# Windows Startup Cleaner
# Safe startup-program analyzer and optional disabler.
# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Scan
#   powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Interactive
#   powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Restore

[CmdletBinding(DefaultParameterSetName = 'Scan')]
param(
    [Parameter(ParameterSetName = 'Scan')]
    [switch]$Scan,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,

    [string]$OutputDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ScriptRoot 'startup-cleaner-output'
}

$KeepPatterns = @(
    'windows defender', 'securityhealth', 'microsoft defender', 'onedrive',
    'explorer', 'ctfmon', 'input', 'ime', 'audio', 'realtek', 'synaptics',
    'touchpad', 'graphics', 'nvidia', 'amd', 'intel', 'driver', 'vpn', 'clash'
)

$OptionalPatterns = @(
    'wechat', 'weixin', 'wechatappex', 'wxwork', 'qq', 'tencent',
    'chrome', 'google update', 'edge update', 'teams', 'skype', 'discord',
    'spotify', 'steam', 'epic', 'adobe', 'creative cloud', 'codepilot',
    'codex', '360', '360安全浏览器', '360safe', '360tray', 'mspcmanager',
    'cc switch', 'wps', 'baidu', 'xunlei', '迅雷'
)

$ReviewPatterns = @(
    'webview', 'runtime', 'update', 'helper', 'service', 'manager', 'assistant'
)

function Ensure-OutputDir {
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -Path $OutputDir -ItemType Directory | Out-Null
    }
}

function Normalize-Text {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return $Text.ToLowerInvariant()
}

function Match-AnyPattern {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        if ($Text -like "*$pattern*") { return $true }
    }
    return $false
}

function Get-ItemSourceKind {
    param([string]$Location)
    if ($Location -like 'HKCU*') { return 'RegistryCurrentUser' }
    if ($Location -like 'HKLM*') { return 'RegistryLocalMachine' }
    if ($Location -like '*Startup*') { return 'StartupFolder' }
    return 'Other'
}

function Classify-StartupItem {
    param($Item)

    $combined = Normalize-Text (($Item.Name, $Item.Command, $Item.Location, $Item.Publisher) -join ' ')
    if (Match-AnyPattern -Text $combined -Patterns $KeepPatterns) {
        return [pscustomobject]@{
            Recommendation = 'KEEP'
            Reason = '可能与系统、安全、输入法、驱动、网络代理等基础功能相关。'
        }
    }
    if (Match-AnyPattern -Text $combined -Patterns $OptionalPatterns) {
        return [pscustomobject]@{
            Recommendation = 'OPTIONAL_DISABLE'
            Reason = '常见非必要自启动；关闭通常不影响系统，可在需要时手动打开。'
        }
    }
    if (Match-AnyPattern -Text $combined -Patterns $ReviewPatterns) {
        return [pscustomobject]@{
            Recommendation = 'REVIEW'
            Reason = '名称像后台组件/更新器，需要确认对应软件是否常用。'
        }
    }
    return [pscustomobject]@{
        Recommendation = 'REVIEW'
        Reason = '未命中规则；建议人工确认用途后再关闭。'
    }
}

function Get-SafePropertyValue {
    param(
        $Object,
        [string]$PropertyName
    )

    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return '' }
    if ($null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function Get-ScheduledTaskActionText {
    param($Action)

    if ($null -eq $Action) { return '' }

    $execute = Get-SafePropertyValue -Object $Action -PropertyName 'Execute'
    $arguments = Get-SafePropertyValue -Object $Action -PropertyName 'Arguments'
    $workingDirectory = Get-SafePropertyValue -Object $Action -PropertyName 'WorkingDirectory'

    $parts = @($execute, $arguments, $workingDirectory) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($parts.Count -gt 0) { return ($parts -join ' ').Trim() }

    return ($Action | Out-String).Trim()
}
function Test-StartupTaskTrigger {
    param($Trigger)

    if ($null -eq $Trigger) { return $false }

    $text = (($Trigger | Format-List * | Out-String), $Trigger.ToString()) -join ' '
    if ($text -match 'Logon|Boot|Startup|AtLogOn|AtStartup|MSFT_TaskLogonTrigger|MSFT_TaskBootTrigger') {
        return $true
    }

    foreach ($propertyName in @('CimClass', 'ClassName', 'TriggerType', 'Type')) {
        $property = $Trigger.PSObject.Properties[$propertyName]
        if ($null -ne $property -and [string]$property.Value -match 'Logon|Boot|Startup') {
            return $true
        }
    }

    return $false
}
function Get-StartupFolderItems {
    $folders = @(
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne 'desktop.ini'
        } | ForEach-Object {
            [pscustomobject]@{
                Name = $_.BaseName
                Command = $_.FullName
                Location = $folder
                User = if ($folder -eq [Environment]::GetFolderPath('Startup')) { $env:USERNAME } else { 'AllUsers' }
                Publisher = ''
                SourceKind = 'StartupFolder'
                Raw = $_
            }
        }
    }
}

function Get-RegistryStartupItems {
    $paths = @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    )

    foreach ($entry in $paths) {
        if (-not (Test-Path -LiteralPath $entry.Path)) { continue }
        $props = Get-ItemProperty -LiteralPath $entry.Path
        foreach ($property in $props.PSObject.Properties) {
            if ($property.Name -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) { continue }
            [pscustomobject]@{
                Name = $property.Name
                Command = [string]$property.Value
                Location = $entry.Path
                User = if ($entry.Hive -eq 'HKCU') { $env:USERNAME } else { 'AllUsers' }
                Publisher = ''
                SourceKind = Get-ItemSourceKind -Location $entry.Path
                Raw = $property
            }
        }
    }
}

function Get-ScheduledStartupTasks {
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    foreach ($task in $tasks) {
        try {
            if ($task.State -eq 'Disabled') { continue }
            $hasStartupTrigger = @($task.Triggers | Where-Object { Test-StartupTaskTrigger -Trigger $_ }).Count -gt 0
            if (-not $hasStartupTrigger) { continue }

            $actions = @($task.Actions | ForEach-Object { Get-ScheduledTaskActionText -Action $_ }) -join '; '
            [pscustomobject]@{
                Name = $task.TaskName
                Command = $actions
                Location = "ScheduledTask:$($task.TaskPath)$($task.TaskName)"
                User = 'TaskScheduler'
                Publisher = (Get-SafePropertyValue -Object $task -PropertyName 'Author')
                SourceKind = 'ScheduledTask'
                Raw = $task
            }
        } catch {
            continue
        }
    }
}

function Get-StartupItems {
    $items = @()
    $items += Get-RegistryStartupItems
    $items += Get-StartupFolderItems
    $items += Get-ScheduledStartupTasks

    $items | ForEach-Object {
        $classification = Classify-StartupItem -Item $_
        [pscustomobject]@{
            Name = $_.Name
            Recommendation = $classification.Recommendation
            Reason = $classification.Reason
            Command = $_.Command
            Location = $_.Location
            User = $_.User
            Publisher = $_.Publisher
            SourceKind = $_.SourceKind
        }
    } | Sort-Object Recommendation, Name
}

function Get-HighMemoryProcesses {
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 30 @{
        Name = 'ProcessName'; Expression = { $_.ProcessName }
    }, Id, @{
        Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) }
    }, @{
        Name = 'CPUSeconds'; Expression = { if ($null -eq $_.CPU) { 0 } else { [math]::Round($_.CPU, 1) } }
    }
}

function Write-Reports {
    param([object[]]$StartupItems, [object[]]$Processes)
    Ensure-OutputDir
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csvPath = Join-Path $OutputDir "startup-report-$timestamp.csv"
    $jsonPath = Join-Path $OutputDir "startup-report-$timestamp.json"
    $processPath = Join-Path $OutputDir "high-memory-processes-$timestamp.csv"

    $StartupItems | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
    $StartupItems | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $jsonPath
    $Processes | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $processPath

    [pscustomobject]@{
        StartupCsv = $csvPath
        StartupJson = $jsonPath
        ProcessCsv = $processPath
    }
}

function Backup-RegistryValue {
    param($Item)
    Ensure-OutputDir
    $backupPath = Join-Path $OutputDir 'disabled-startup-backup.json'
    $backups = @()
    if (Test-Path -LiteralPath $backupPath) {
        $content = Get-Content -LiteralPath $backupPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) { $backups = @($content | ConvertFrom-Json) }
    }
    $backups += [pscustomobject]@{
        DisabledAt = (Get-Date).ToString('s')
        Name = $Item.Name
        Command = $Item.Command
        Location = $Item.Location
        SourceKind = $Item.SourceKind
    }
    $backups | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $backupPath
}

function Disable-StartupItem {
    param($Item)

    if ($Item.SourceKind -like 'Registry*') {
        Backup-RegistryValue -Item $Item
        Remove-ItemProperty -LiteralPath $Item.Location -Name $Item.Name
        return "已禁用注册表启动项：$($Item.Name)"
    }

    if ($Item.SourceKind -eq 'StartupFolder') {
        Ensure-OutputDir
        $disabledDir = Join-Path $OutputDir 'disabled-startup-folder-items'
        if (-not (Test-Path -LiteralPath $disabledDir)) { New-Item -Path $disabledDir -ItemType Directory | Out-Null }
        $source = $Item.Command
        if (Test-Path -LiteralPath $source) {
            Move-Item -LiteralPath $source -Destination (Join-Path $disabledDir (Split-Path $source -Leaf))
            return "已移动启动文件夹项目：$($Item.Name)"
        }
    }

    if ($Item.SourceKind -eq 'ScheduledTask') {
        Backup-RegistryValue -Item $Item
        $taskName = $Item.Name
        Disable-ScheduledTask -TaskName $taskName | Out-Null
        return "已禁用计划任务：$($Item.Name)"
    }

    return "跳过不支持的项目：$($Item.Name)"
}

function Restore-DisabledItems {
    Ensure-OutputDir
    $backupPath = Join-Path $OutputDir 'disabled-startup-backup.json'
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Write-Host '没有找到可恢复的注册表/计划任务备份。'
        return
    }

    $backups = @(Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json)
    foreach ($backup in $backups) {
        if ($backup.SourceKind -like 'Registry*') {
            if (-not (Test-Path -LiteralPath $backup.Location)) { New-Item -Path $backup.Location -Force | Out-Null }
            New-ItemProperty -LiteralPath $backup.Location -Name $backup.Name -Value $backup.Command -PropertyType String -Force | Out-Null
            Write-Host "已恢复注册表启动项：$($backup.Name)"
        } elseif ($backup.SourceKind -eq 'ScheduledTask') {
            Enable-ScheduledTask -TaskName $backup.Name | Out-Null
            Write-Host "已恢复计划任务：$($backup.Name)"
        }
    }

    $disabledDir = Join-Path $OutputDir 'disabled-startup-folder-items'
    if (Test-Path -LiteralPath $disabledDir) {
        Write-Host "启动文件夹项目保存在：$disabledDir，请按需手动移回启动文件夹。"
    }
}

function Start-InteractiveCleanup {
    $items = @(Get-StartupItems)
    $processes = @(Get-HighMemoryProcesses)
    $reportPaths = Write-Reports -StartupItems $items -Processes $processes

    Write-Host "`n已生成报告：$($reportPaths.StartupCsv)"
    Write-Host '建议只禁用 OPTIONAL_DISABLE；KEEP 不会被本工具自动禁用。'

    $candidates = @($items | Where-Object { $_.Recommendation -eq 'OPTIONAL_DISABLE' })
    if ($candidates.Count -eq 0) {
        Write-Host '没有发现明确可选的自启动项。'
        return
    }

    for ($index = 0; $index -lt $candidates.Count; $index++) {
        $item = $candidates[$index]
        Write-Host ("[{0}] {1} | {2} | {3}" -f ($index + 1), $item.Name, $item.SourceKind, $item.Reason)
        Write-Host "    $($item.Command)"
    }

    Write-Host "`n输入要禁用的编号，用逗号分隔；直接回车则不禁用任何项目。"
    $answer = Read-Host '编号'
    if ([string]::IsNullOrWhiteSpace($answer)) {
        Write-Host '未禁用任何启动项。'
        return
    }

    $numbers = $answer -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($number in $numbers) {
        if ($number -lt 1 -or $number -gt $candidates.Count) {
            Write-Host "跳过无效编号：$number"
            continue
        }
        $result = Disable-StartupItem -Item $candidates[$number - 1]
        Write-Host $result
    }

    Write-Host "`n完成。建议重启后观察内存，如有问题运行：powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Restore"
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Restore) {
        Restore-DisabledItems
        exit
    }

    if ($Interactive) {
        Start-InteractiveCleanup
        exit
    }

    $startupItems = @(Get-StartupItems)
    $highMemoryProcesses = @(Get-HighMemoryProcesses)
    $paths = Write-Reports -StartupItems $startupItems -Processes $highMemoryProcesses

    Write-Host "`n启动项识别结果："
    $startupItems | Format-Table -AutoSize Name, Recommendation, SourceKind, User, Reason

    Write-Host "`n当前内存占用最高进程："
    $highMemoryProcesses | Format-Table -AutoSize ProcessName, Id, MemoryMB, CPUSeconds

    Write-Host "`n报告已保存："
    Write-Host "  $($paths.StartupCsv)"
    Write-Host "  $($paths.StartupJson)"
    Write-Host "  $($paths.ProcessCsv)"

    Write-Host "`n如需按编号选择禁用可选启动项，请运行："
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\StartupCleaner.ps1 -Interactive'
}



