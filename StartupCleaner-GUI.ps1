# Windows Startup Cleaner GUI
# Double-click Launch-StartupCleaner-GUI.bat, or run:
# powershell -ExecutionPolicy Bypass -File .\StartupCleaner-GUI.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$CoreScript = Join-Path $ScriptRoot 'StartupCleaner.ps1'
if (-not (Test-Path -LiteralPath $CoreScript)) {
    [System.Windows.Forms.MessageBox]::Show("找不到核心脚本：$CoreScript", '启动项清理工具', 'OK', 'Error') | Out-Null
    exit 1
}

. $CoreScript

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:StartupItems = @()
$script:HighMemoryProcesses = @()
$script:LastReportPaths = $null

function Show-Info {
    param([string]$Message, [string]$Title = '启动项清理工具')
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
}

function Show-Warning {
    param([string]$Message, [string]$Title = '启动项清理工具')
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Warning') | Out-Null
}

function Show-ErrorBox {
    param([string]$Message, [string]$Title = '启动项清理工具')
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
}

function Confirm-Action {
    param([string]$Message, [string]$Title = '请确认')
    $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'YesNo', 'Question')
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function New-ColumnHeader {
    param([string]$Text, [int]$Width)
    $column = New-Object System.Windows.Forms.ColumnHeader
    $column.Text = $Text
    $column.Width = $Width
    return $column
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '开机启动项清理工具 - 安全版'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1120, 760)
$form.MinimumSize = New-Object System.Drawing.Size(980, 640)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$header = New-Object System.Windows.Forms.Label
$header.Text = '先点击“扫描”，勾选建议可关闭的启动项，再点击“禁用勾选项”。不确定的项目请先别动。'
$header.AutoSize = $false
$header.Height = 34
$header.Dock = 'Top'
$header.TextAlign = 'MiddleLeft'
$header.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
$form.Controls.Add($header)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Height = 48
$buttonPanel.Dock = 'Top'
$form.Controls.Add($buttonPanel)

$scanButton = New-Object System.Windows.Forms.Button
$scanButton.Text = '扫描启动项'
$scanButton.Size = New-Object System.Drawing.Size(110, 30)
$scanButton.Location = New-Object System.Drawing.Point(10, 9)
$buttonPanel.Controls.Add($scanButton)

$disableButton = New-Object System.Windows.Forms.Button
$disableButton.Text = '禁用勾选项'
$disableButton.Size = New-Object System.Drawing.Size(110, 30)
$disableButton.Location = New-Object System.Drawing.Point(130, 9)
$disableButton.Enabled = $false
$buttonPanel.Controls.Add($disableButton)

$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Text = '恢复已禁用'
$restoreButton.Size = New-Object System.Drawing.Size(110, 30)
$restoreButton.Location = New-Object System.Drawing.Point(250, 9)
$buttonPanel.Controls.Add($restoreButton)

$openReportButton = New-Object System.Windows.Forms.Button
$openReportButton.Text = '打开报告文件夹'
$openReportButton.Size = New-Object System.Drawing.Size(130, 30)
$openReportButton.Location = New-Object System.Drawing.Point(370, 9)
$buttonPanel.Controls.Add($openReportButton)

$checkOptionalButton = New-Object System.Windows.Forms.Button
$checkOptionalButton.Text = '勾选建议关闭'
$checkOptionalButton.Size = New-Object System.Drawing.Size(120, 30)
$checkOptionalButton.Location = New-Object System.Drawing.Point(510, 9)
$checkOptionalButton.Enabled = $false
$buttonPanel.Controls.Add($checkOptionalButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = '状态：等待扫描'
$statusLabel.AutoSize = $false
$statusLabel.Location = New-Object System.Drawing.Point(645, 14)
$statusLabel.Size = New-Object System.Drawing.Size(430, 22)
$buttonPanel.Controls.Add($statusLabel)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Horizontal'
$split.SplitterDistance = 430
$form.Controls.Add($split)
$form.Controls.SetChildIndex($split, 0)

$startupGroup = New-Object System.Windows.Forms.GroupBox
$startupGroup.Text = '开机自启动项'
$startupGroup.Dock = 'Fill'
$split.Panel1.Controls.Add($startupGroup)

$startupList = New-Object System.Windows.Forms.ListView
$startupList.Dock = 'Fill'
$startupList.View = 'Details'
$startupList.FullRowSelect = $true
$startupList.GridLines = $true
$startupList.CheckBoxes = $true
$startupList.HideSelection = $false
[void]$startupList.Columns.Add((New-ColumnHeader '建议' 130))
[void]$startupList.Columns.Add((New-ColumnHeader '名称' 190))
[void]$startupList.Columns.Add((New-ColumnHeader '来源' 130))
[void]$startupList.Columns.Add((New-ColumnHeader '用户' 110))
[void]$startupList.Columns.Add((New-ColumnHeader '原因' 330))
[void]$startupList.Columns.Add((New-ColumnHeader '命令/路径' 520))
$startupGroup.Controls.Add($startupList)

$processGroup = New-Object System.Windows.Forms.GroupBox
$processGroup.Text = '当前内存占用最高的进程（仅供参考，不会自动结束）'
$processGroup.Dock = 'Fill'
$split.Panel2.Controls.Add($processGroup)

$processList = New-Object System.Windows.Forms.ListView
$processList.Dock = 'Fill'
$processList.View = 'Details'
$processList.FullRowSelect = $true
$processList.GridLines = $true
[void]$processList.Columns.Add((New-ColumnHeader '进程名' 220))
[void]$processList.Columns.Add((New-ColumnHeader 'PID' 90))
[void]$processList.Columns.Add((New-ColumnHeader '内存 MB' 100))
[void]$processList.Columns.Add((New-ColumnHeader 'CPU 秒' 100))
$processGroup.Controls.Add($processList)

$legend = New-Object System.Windows.Forms.Label
$legend.Text = '说明：KEEP=建议保留；OPTIONAL_DISABLE=通常可关闭；REVIEW=需要你确认用途。关闭自启动不等于卸载软件。'
$legend.Dock = 'Bottom'
$legend.Height = 30
$legend.TextAlign = 'MiddleLeft'
$legend.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
$form.Controls.Add($legend)

function Set-Busy {
    param([bool]$Busy, [string]$Text)
    $scanButton.Enabled = -not $Busy
    $disableButton.Enabled = (-not $Busy) -and ($startupList.Items.Count -gt 0)
    $restoreButton.Enabled = -not $Busy
    $checkOptionalButton.Enabled = (-not $Busy) -and ($startupList.Items.Count -gt 0)
    $statusLabel.Text = "状态：$Text"
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-StartupRow {
    param($Item)
    $row = New-Object System.Windows.Forms.ListViewItem($Item.Recommendation)
    [void]$row.SubItems.Add($Item.Name)
    [void]$row.SubItems.Add($Item.SourceKind)
    [void]$row.SubItems.Add($Item.User)
    [void]$row.SubItems.Add($Item.Reason)
    [void]$row.SubItems.Add($Item.Command)
    $row.Tag = $Item

    if ($Item.Recommendation -eq 'OPTIONAL_DISABLE') {
        $row.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 220)
    } elseif ($Item.Recommendation -eq 'KEEP') {
        $row.BackColor = [System.Drawing.Color]::FromArgb(225, 245, 225)
    } else {
        $row.BackColor = [System.Drawing.Color]::FromArgb(235, 242, 255)
    }

    [void]$startupList.Items.Add($row)
}

function Add-ProcessRow {
    param($Process)
    $row = New-Object System.Windows.Forms.ListViewItem($Process.ProcessName)
    [void]$row.SubItems.Add([string]$Process.Id)
    [void]$row.SubItems.Add([string]$Process.MemoryMB)
    [void]$row.SubItems.Add([string]$Process.CPUSeconds)
    [void]$processList.Items.Add($row)
}

function Refresh-Data {
    try {
        Set-Busy $true '正在扫描，请稍等...'
        $startupList.Items.Clear()
        $processList.Items.Clear()

        $script:StartupItems = @(Get-StartupItems)
        $script:HighMemoryProcesses = @(Get-HighMemoryProcesses)
        $script:LastReportPaths = Write-Reports -StartupItems $script:StartupItems -Processes $script:HighMemoryProcesses

        foreach ($item in $script:StartupItems) { Add-StartupRow -Item $item }
        foreach ($process in $script:HighMemoryProcesses) { Add-ProcessRow -Process $process }

        $optionalCount = @($script:StartupItems | Where-Object { $_.Recommendation -eq 'OPTIONAL_DISABLE' }).Count
        Set-Busy $false "扫描完成：发现 $optionalCount 个通常可关闭启动项"
    } catch {
        Set-Busy $false '扫描失败'
        Show-ErrorBox "扫描失败：$($_.Exception.Message)"
    }
}

$scanButton.Add_Click({ Refresh-Data })

$checkOptionalButton.Add_Click({
    foreach ($row in $startupList.Items) {
        $row.Checked = ($row.Tag.Recommendation -eq 'OPTIONAL_DISABLE')
    }
})

$disableButton.Add_Click({
    $selectedRows = @($startupList.Items | Where-Object { $_.Checked })
    if ($selectedRows.Count -eq 0) {
        Show-Warning '请先勾选要禁用的启动项。建议只勾选黄色的 OPTIONAL_DISABLE。'
        return
    }

    $keepRows = @($selectedRows | Where-Object { $_.Tag.Recommendation -eq 'KEEP' })
    if ($keepRows.Count -gt 0) {
        Show-Warning '你勾选了 KEEP 项。为避免影响系统、驱动或安全功能，本工具不会禁用 KEEP 项。'
        foreach ($row in $keepRows) { $row.Checked = $false }
        $selectedRows = @($startupList.Items | Where-Object { $_.Checked })
        if ($selectedRows.Count -eq 0) { return }
    }

    $reviewRows = @($selectedRows | Where-Object { $_.Tag.Recommendation -eq 'REVIEW' })
    if ($reviewRows.Count -gt 0) {
        $reviewNames = ($reviewRows | ForEach-Object { $_.Tag.Name }) -join '、'
        if (-not (Confirm-Action "你选择了需要人工确认的项目：$reviewNames`n`n不确定的话建议点“否”。确定要继续吗？" '确认禁用 REVIEW 项')) {
            return
        }
    }

    $names = ($selectedRows | ForEach-Object { $_.Tag.Name }) -join '、'
    if (-not (Confirm-Action "即将禁用这些开机自启动项：`n$names`n`n这不会卸载软件，之后可尝试恢复。确定继续吗？" '确认禁用')) {
        return
    }

    $results = New-Object System.Collections.Generic.List[string]
    try {
        Set-Busy $true '正在禁用勾选项...'
        foreach ($row in $selectedRows) {
            try {
                $results.Add((Disable-StartupItem -Item $row.Tag))
            } catch {
                $results.Add("失败：$($row.Tag.Name) - $($_.Exception.Message)")
            }
        }
        Set-Busy $false '禁用完成，正在刷新...'
        Refresh-Data
        Show-Info (($results -join "`n") + "`n`n建议重启电脑后观察内存占用。")
    } catch {
        Set-Busy $false '禁用失败'
        Show-ErrorBox "禁用失败：$($_.Exception.Message)`n`n如果是权限问题，请右键启动器，选择以管理员身份运行。"
    }
})

$restoreButton.Add_Click({
    if (-not (Confirm-Action '确定要恢复本工具之前禁用过的注册表启动项和计划任务吗？' '确认恢复')) { return }
    try {
        Set-Busy $true '正在恢复...'
        Restore-DisabledItems
        Set-Busy $false '恢复完成，正在刷新...'
        Refresh-Data
        Show-Info '恢复完成。启动文件夹中被移动的项目会在报告目录中保留，请按提示手动移回。'
    } catch {
        Set-Busy $false '恢复失败'
        Show-ErrorBox "恢复失败：$($_.Exception.Message)`n`n如果是权限问题，请右键启动器，选择以管理员身份运行。"
    }
})

$openReportButton.Add_Click({
    try {
        Ensure-OutputDir
        Start-Process -FilePath $OutputDir
    } catch {
        Show-ErrorBox "无法打开报告文件夹：$($_.Exception.Message)"
    }
})

$form.Add_Shown({ Refresh-Data })
[void][System.Windows.Forms.Application]::Run($form)
