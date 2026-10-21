# Windows GUI helper (also used from WSL). Windows Hello draws the PIN and touch prompts
# itself, so this only shows which push is waiting for approval.
param(
    [string]$Repository = 'Unknown repository',
    [string]$Remote = 'Unknown remote',
    # The window closes once this path is gone (the hook deletes its work directory on exit).
    [string]$WatchPath
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-Label([string]$Text, [float]$Size, [bool]$Strong = $false) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleCenter'
    $label.AutoEllipsis = $true
    $style = if ($Strong) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $style)
    $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'YubiKey Git Approval'
$form.ClientSize = New-Object System.Drawing.Size(440, 250)
$form.FormBorderStyle = 'FixedDialog'
$form.ControlBox = $false
$form.TopMost = $true
$form.ShowInTaskbar = $true
# Top of the screen, clear of the centered Windows Hello dialog.
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(($area.X + ($area.Width - $form.Width) / 2), ($area.Y + 40))

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 16)
$layout.ColumnCount = 1
$layout.RowCount = 6
1..6 | ForEach-Object { $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 16.6))) | Out-Null }
$layout.Controls.Add((New-Label 'Touch your YubiKey' 16 $true))
$layout.Controls.Add((New-Label 'Physical presence required to authorize Git push' 9))
$layout.Controls.Add((New-Label "Repository: $Repository" 10 $true))
$layout.Controls.Add((New-Label "Remote: $Remote" 9))
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = 'Marquee'
$progress.Dock = 'Fill'
$progress.Margin = New-Object System.Windows.Forms.Padding(60, 8, 60, 8)
$layout.Controls.Add($progress)
$layout.Controls.Add((New-Label 'Enter your PIN in the Windows Security prompt if asked' 9))
$form.Controls.Add($layout)

$form.Add_Shown({
    if ($WatchPath) { New-Item -ItemType File -Path (Join-Path $WatchPath 'gui-ready') -Force | Out-Null }
})
# Also close after 5 minutes, in case nobody removes WatchPath (or none was given).
$started = [System.Diagnostics.Stopwatch]::StartNew()
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $gone = $WatchPath -and -not (Test-Path -LiteralPath $WatchPath)
    if ($gone -or $started.Elapsed.TotalMinutes -ge 5) { $form.Close() }
})
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
