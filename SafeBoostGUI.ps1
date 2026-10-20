<#
.SYNOPSIS
    SafeBoost - graphical app (Windows 10/11).

.DESCRIPTION
    Same engine as SafeBoost.ps1 (every change backed up and reversible), with a
    Windows 11 style interface. All work runs on a background thread so the window
    never freezes.

.PARAMETER Screenshot
    Render every page to PNG files in this folder and exit (used to make README images).

.PARAMETER Theme
    Light, Dark or System (default follows the Windows app theme).
#>
[CmdletBinding()]
param(
    [string]$Screenshot,
    [ValidateSet('System','Light','Dark')][string]$Theme = 'System'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Theme',$Theme)
    if ($Screenshot) { $a += '-Screenshot', "`"$Screenshot`"" }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @a
    exit $LASTEXITCODE
}

$script:Root = $PSScriptRoot
. "$script:Root\lib\Core.ps1"
. "$script:Root\lib\Tweaks.ps1"
. "$script:Root\lib\Analyze.ps1"

if (-not $Screenshot -and -not (Test-SBAdmin)) {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Theme $Theme"
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# ==================================================================== state
$script:AppCfg     = Get-Content -LiteralPath "$script:Root\config\apps.json" -Raw | ConvertFrom-Json
$script:AllTweaks  = @(Get-SBTweaks)
$script:TweakChecks = [ordered]@{}      # id -> CheckBox
$script:TweakCards  = @()               # @{ Card; Rows; Counter }
$script:AppSel      = @{}               # pattern -> bool
$script:Installed   = $null             # array of installed package names (null = still scanning)
$script:PresetCards = @{}
$script:Preset      = 'Gaming'
$script:Jobs        = New-Object System.Collections.ArrayList
$script:LogQueue    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$global:SBLogQueue  = $script:LogQueue
$script:LogTarget   = 'apply'
$script:Busy        = $false
$script:LastSession = $null
$script:Pages       = @('Overview','Tweaks','Apps','Apply','Undo')
$script:Dot         = ' ' + [char]0x00B7 + ' '
$script:Dash        = ' ' + [char]0x2014 + ' '
function Get-Plural([int]$n, [string]$word) { if ($n -eq 1) { "$n $word" } else { "$n ${word}s" } }

$script:Friendly = @{
    'Microsoft.BingNews' = 'Microsoft News'; 'Microsoft.BingWeather' = 'Weather'; 'Microsoft.BingSearch' = 'Bing Search'
    'Microsoft.News' = 'News'; 'Microsoft.Getstarted' = 'Tips'; 'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365 hub'
    'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire Collection'; 'Microsoft.People' = 'People'
    'Microsoft.PowerAutomateDesktop' = 'Power Automate'; 'Microsoft.Todos' = 'Microsoft To Do'
    'Microsoft.WindowsFeedbackHub' = 'Feedback Hub'; 'Microsoft.ZuneVideo' = 'Films & TV'
    'Microsoft.MixedReality.Portal' = 'Mixed Reality Portal'; 'Microsoft.Microsoft3DViewer' = '3D Viewer'
    'Microsoft.MSPaint' = 'Paint 3D'; 'Microsoft.Print3D' = 'Print 3D'; 'Microsoft.SkypeApp' = 'Skype'
    'Microsoft.WindowsMaps' = 'Maps'; 'Microsoft.Messaging' = 'Messaging'; 'Microsoft.OneConnect' = 'Mobile Plans'
    'Microsoft.Wallet' = 'Wallet'; 'Microsoft.549981C3F5F10' = 'Cortana'; 'Microsoft.Copilot' = 'Copilot app'
    'MicrosoftTeams' = 'Teams (personal)'; 'MicrosoftCorporationII.MicrosoftFamily' = 'Family Safety'
    'Clipchamp.Clipchamp' = 'Clipchamp'; 'microsoft.windowscommunicationsapps' = 'Mail & Calendar'
    'Microsoft.OutlookForWindows' = 'Outlook (new)'; 'Microsoft.YourPhone' = 'Phone Link'; 'Microsoft.Office.OneNote' = 'OneNote'
    'Microsoft.Whiteboard' = 'Whiteboard'; 'Microsoft.XboxApp' = 'Xbox Console Companion (old)'; 'MSTeams' = 'Teams (work/school)'
    'SpotifyAB.SpotifyMusic' = 'Spotify'
}

$script:CatDefs = [ordered]@{
    'Gaming'     = @{ Title = 'Gaming & latency';        Glyph = 0xE7FC; Col = 0 }
    'Privacy'    = @{ Title = 'Privacy & ads';           Glyph = 0xE72E; Col = 1 }
    'Max'        = @{ Title = 'Lean mode (low-end PCs)'; Glyph = 0xE790; Col = 1 }
    'Background' = @{ Title = 'Background activity';     Glyph = 0xE9F5; Col = 2 }
    'Speed'      = @{ Title = 'Speed & cleanup';         Glyph = 0xEC4A; Col = 2 }
    'Extras'     = @{ Title = 'Quality of life';         Glyph = 0xE734; Col = 2 }
}
function Get-CatKey($c) { if ($c -in 'Responsiveness','Cleanup') { 'Speed' } else { $c } }

$script:Themes = @{
    Light = @{ BgBrush='#F3F3F3'; ContentBrush='#F9F9F9'; CardBrush='#FFFFFF'; CardBorderBrush='#E5E5E5'; TextBrush='#1A1A1A'
               SubTextBrush='#616161'; AccentBrush='#0F6CBD'; AccentHoverBrush='#115EA3'; AccentFgBrush='#FFFFFF'; AccentSoftBrush='#1A0F6CBD'
               HoverBrush='#0A000000'; PressedBrush='#14000000'; InputBrush='#FFFFFF'; CheckBorderBrush='#8A8A8A'; ScrollBrush='#C2C2C2'
               LogBrush='#F7F7F7'; SevBigBrush='#C42B1C'; SevBigBgBrush='#1AC42B1C'; SevWarnBrush='#9D5D00'; SevWarnBgBrush='#1F9D5D00'
               SevOkBrush='#0F7B0F'; SevOkBgBrush='#1A0F7B0F' }
    Dark  = @{ BgBrush='#1C1C1C'; ContentBrush='#242424'; CardBrush='#2C2C2C'; CardBorderBrush='#383838'; TextBrush='#FFFFFF'
               SubTextBrush='#ADADAD'; AccentBrush='#60CDFF'; AccentHoverBrush='#5AB8E8'; AccentFgBrush='#00121F'; AccentSoftBrush='#2660CDFF'
               HoverBrush='#0FFFFFFF'; PressedBrush='#1AFFFFFF'; InputBrush='#262626'; CheckBorderBrush='#9E9E9E'; ScrollBrush='#5C5C5C'
               LogBrush='#1F1F1F'; SevBigBrush='#FF99A4'; SevBigBgBrush='#33FF99A4'; SevWarnBrush='#FCE100'; SevWarnBgBrush='#26FCE100'
               SevOkBrush='#6CCB5F'; SevOkBgBrush='#266CCB5F' }
}

# ==================================================================== window
$xamlText = Get-Content -LiteralPath "$script:Root\lib\MainWindow.xaml" -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xamlText)))
$ui = @{}
foreach ($m in [regex]::Matches($xamlText, 'x:Name="([A-Za-z0-9_]+)"')) {
    $n = $m.Groups[1].Value
    $el = $window.FindName($n)
    if ($el) { $ui[$n] = $el }
}
$ui.TxtVersion.Text = "v$script:SBVersion"

# ==================================================================== small UI helpers
function Set-Ref($el, $prop, $key) { $el.SetResourceReference($prop, $key) }

function New-TB {
    param([string]$Text, [string]$Brush = 'TextBrush', [double]$Size = 13, [string]$Weight = 'Normal', [switch]$Wrap)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size
    $t.FontWeight = [Windows.FontWeights]::$Weight
    Set-Ref $t ([Windows.Controls.TextBlock]::ForegroundProperty) $Brush
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function New-Glyph {
    param([int]$Code, [string]$Brush = 'TextBrush', [double]$Size = 14)
    $t = New-TB -Text ([string][char]$Code) -Brush $Brush -Size $Size
    $t.FontFamily = New-Object Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
    $t.VerticalAlignment = 'Center'
    return $t
}

function New-Pill {
    param([string]$Text, [string]$Fg = 'AccentBrush', [string]$Bg = 'AccentSoftBrush')
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = 4; $b.Padding = '6,1,6,2'; $b.Margin = '0,0,6,0'; $b.VerticalAlignment = 'Center'
    Set-Ref $b ([Windows.Controls.Border]::BackgroundProperty) $Bg
    $b.Child = New-TB -Text $Text -Brush $Fg -Size 11 -Weight 'SemiBold'
    return $b
}

function New-Card {
    param([string]$Margin = '0,0,0,14')
    $b = New-Object Windows.Controls.Border
    $b.Style = $window.FindResource('Card'); $b.Margin = $Margin
    return $b
}

# ==================================================================== theme
function Set-SBTheme([string]$Name) {
    foreach ($kv in $script:Themes[$Name].GetEnumerator()) {
        $brush = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]([Windows.Media.ColorConverter]::ConvertFromString($kv.Value)))
        $brush.Freeze()
        # Remove/Add (not the indexer) so WPF gets the raw Brush, not a PowerShell wrapper object
        if ($window.Resources.Contains($kv.Key)) { $window.Resources.Remove($kv.Key) }
        $window.Resources.Add($kv.Key, $brush)
    }
    $script:ThemeName = $Name
    $ui.GlyphTheme.Text = if ($Name -eq 'Dark') { [string][char]0xE706 } else { [string][char]0xE708 }
}
function Get-SystemTheme {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    if ($v -eq 0) { 'Dark' } else { 'Light' }
}

# ==================================================================== navigation
function Show-Page([string]$Name) {
    foreach ($p in $script:Pages) { $ui["Page$p"].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' } }
    $script:CurrentPage = $Name
    $nav = $ui["Nav$Name"]; if (-not $nav.IsChecked) { $nav.IsChecked = $true }
    $idx = [array]::IndexOf($script:Pages, $Name)
    $ui.BtnBack.IsEnabled = ($idx -gt 0)
    $ui.BtnNext.Visibility = if ($Name -in 'Apply','Undo') { 'Collapsed' } else { 'Visible' }
    $ui.BtnNextText.Text = switch ($Name) { 'Overview' { 'Choose tweaks' } 'Tweaks' { 'Apps' } 'Apps' { 'Review' } default { 'Next' } }
    if ($Name -eq 'Undo') { Update-Runs }
}

# ==================================================================== background jobs
function Start-SBBackground {
    param([string]$Work, [object[]]$Arguments, [scriptblock]$OnComplete)
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('SBLogQueue', $script:LogQueue)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Work)
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    [void]$script:Jobs.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); OnComplete = $OnComplete })
}

function Add-LogLine([string]$Line) {
    if ($Line -match '^@@P (\d+) (\d+)$') {
        $i = [int]$Matches[1]; $n = [int]$Matches[2]
        if ($n -gt 0) { $ui.ApplyProgress.Value = [math]::Round($i / $n * 100) }
        $ui.ApplyStatus.Text = "Working... $i of $n"
        return
    }
    $time = ''; $lvl = 'INFO'; $msg = $Line
    if ($Line -match '^\[(\d\d:\d\d:\d\d)\] \[(\w+)\s*\] (.*)$') { $time = $Matches[1]; $lvl = $Matches[2]; $msg = $Matches[3] }
    $brush = switch ($lvl) { 'OK' { 'SevOkBrush' } 'WARN' { 'SevWarnBrush' } 'ERR' { 'SevBigBrush' } 'DRY' { 'AccentBrush' } 'STEP' { 'TextBrush' } default { 'SubTextBrush' } }
    $mono = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $g = New-Object Windows.Controls.Grid
    foreach ($w in 70, 52, -1) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -lt 0) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength $w }
        $g.ColumnDefinitions.Add($cd)
    }
    $g.Margin = if ($lvl -eq 'STEP') { '0,8,0,1' } else { '0,1' }
    $t1 = New-TB -Text $time -Brush 'SubTextBrush' -Size 12; $t1.FontFamily = $mono; $t1.Opacity = 0.7
    $t2 = New-TB -Text $lvl -Brush $brush -Size 12 -Weight 'SemiBold'; $t2.FontFamily = $mono; [Windows.Controls.Grid]::SetColumn($t2, 1)
    $t3 = New-TB -Text $msg -Brush $(if ($lvl -eq 'STEP') { 'TextBrush' } else { 'SubTextBrush' }) -Size 12 -Weight $(if ($lvl -eq 'STEP') { 'SemiBold' } else { 'Normal' }) -Wrap
    $t3.FontFamily = $mono; [Windows.Controls.Grid]::SetColumn($t3, 2)
    [void]$g.Children.Add($t1); [void]$g.Children.Add($t2); [void]$g.Children.Add($t3)
    $panel = if ($script:LogTarget -eq 'undo') { $ui.UndoLogPanel } else { $ui.LogPanel }
    [void]$panel.Children.Add($g)
    while ($panel.Children.Count -gt 1500) { $panel.Children.RemoveAt(0) }
}

function Invoke-Pump {
    $line = $null; $n = 0
    while ($n -lt 400 -and $script:LogQueue.TryDequeue([ref]$line)) { Add-LogLine $line; $n++ }
    if ($n -gt 0) { if ($script:LogTarget -eq 'apply') { $ui.LogScroll.ScrollToEnd() } }
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        [void]$script:Jobs.Remove($j)
        $result = $null; $err = $null
        try { $result = $j.PS.EndInvoke($j.Handle) } catch { $err = $_.Exception.Message }
        if (-not $err -and $j.PS.Streams.Error.Count) { $err = ($j.PS.Streams.Error | Select-Object -First 3 | ForEach-Object { $_.ToString() }) -join "`n" }
        $j.PS.Runspace.Close(); $j.PS.Dispose()
        while ($script:LogQueue.TryDequeue([ref]$line)) { Add-LogLine $line }
        try { & $j.OnComplete $result $err }
        catch { Add-LogLine "[--:--:--] [ERR ] UI error: $($_.Exception.Message)" }
    }
}

# ==================================================================== overview
function Show-Overview($Info, $Findings) {
    $ui.StatTiles.Children.Clear()
    $tiles = @(
        @{ G = 0xE7F8; L = 'Windows';  V = $Info.Windows; D = $Info.WindowsDetail }
        @{ G = 0xE950; L = 'Processor'; V = $Info.Cpu;     D = $Info.CpuDetail }
        @{ G = 0xE7F4; L = 'Graphics';  V = $Info.Gpu;     D = $Info.GpuDetail }
        @{ G = 0xEEA0; L = 'Memory';    V = $Info.Ram;     D = "$($Info.RamDetail)" }
    )
    foreach ($t in $tiles) {
        $c = New-Card -Margin '6,0'
        $c.Padding = '16,14'
        $sp = New-Object Windows.Controls.StackPanel
        $hdr = New-Object Windows.Controls.StackPanel; $hdr.Orientation = 'Horizontal'
        [void]$hdr.Children.Add((New-Glyph -Code $t.G -Brush 'AccentBrush' -Size 14))
        $l = New-TB -Text $t.L -Brush 'SubTextBrush' -Size 12; $l.Margin = '8,0,0,0'; [void]$hdr.Children.Add($l)
        [void]$sp.Children.Add($hdr)
        $v = New-TB -Text "$($t.V)" -Size 15 -Weight 'SemiBold'; $v.Margin = '0,8,0,2'; $v.TextTrimming = 'CharacterEllipsis'; $v.ToolTip = "$($t.V)"
        [void]$sp.Children.Add($v)
        $d = New-TB -Text "$($t.D)" -Brush 'SubTextBrush' -Size 12; $d.TextTrimming = 'CharacterEllipsis'; $d.ToolTip = "$($t.D)"
        [void]$sp.Children.Add($d)
        $c.Child = $sp
        [void]$ui.StatTiles.Children.Add($c)
    }

    $ui.FindingsPanel.Children.Clear()
    $order = @{ BIG = 0; WARN = 1; TIP = 2; INFO = 3 }
    $show = @($Findings | Where-Object { $_.Severity -ne 'INFO' } | Sort-Object { $order[$_.Severity] })
    $big = @($show | Where-Object Severity -eq 'BIG').Count
    $ui.HealthStatus.Text = if ($big) { "$(Get-Plural $big 'high-impact item') found" } elseif ($show.Count) { Get-Plural $show.Count 'suggestion' } else { 'Looking good' }
    if (-not $show.Count) {
        $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        [void]$row.Children.Add((New-Glyph -Code 0xE930 -Brush 'SevOkBrush' -Size 16))
        $t = New-TB -Text 'No hardware, driver or power problems found.' ; $t.Margin = '10,0,0,0'; [void]$row.Children.Add($t)
        [void]$ui.FindingsPanel.Children.Add($row)
    }
    foreach ($f in $show) {
        $map = switch ($f.Severity) {
            'BIG'  { @('High impact', 'SevBigBrush', 'SevBigBgBrush', 0xEA39) }
            'WARN' { @('Attention', 'SevWarnBrush', 'SevWarnBgBrush', 0xE7BA) }
            default { @('Tip', 'AccentBrush', 'AccentSoftBrush', 0xEA80) }
        }
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,10,0,0'
        $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = New-Object Windows.GridLength 104
        $c1 = New-Object Windows.Controls.ColumnDefinition
        $g.ColumnDefinitions.Add($c0); $g.ColumnDefinitions.Add($c1)
        $pill = New-Pill -Text $map[0] -Fg $map[1] -Bg $map[2]; $pill.HorizontalAlignment = 'Left'; $pill.VerticalAlignment = 'Top'; $pill.Margin = '0,1,0,0'
        [void]$g.Children.Add($pill)
        $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
        [void]$sp.Children.Add((New-TB -Text $f.Finding -Weight 'SemiBold' -Wrap))
        if ($f.Fix) { $fx = New-TB -Text $f.Fix -Brush 'SubTextBrush' -Size 12 -Wrap; $fx.Margin = '0,2,0,0'; [void]$sp.Children.Add($fx) }
        [void]$g.Children.Add($sp)
        [void]$ui.FindingsPanel.Children.Add($g)
    }
}

function Build-PresetCards {
    $defs = @(
        @{ Id = 'Safe';   G = 0xEA18; T = 'Safe';   D = 'Debloat, privacy and cleanup. Good for any PC.' }
        @{ Id = 'Gaming'; G = 0xE7FC; T = 'Gaming'; D = 'Safe plus FPS and input-latency tweaks.'; R = $true }
        @{ Id = 'Max';    G = 0xE945; T = 'Max';    D = 'Gaming plus lean visuals. For low-end PCs.' }
        @{ Id = 'Custom'; G = 0xE713; T = 'Custom'; D = 'Start empty and pick every tweak yourself.' }
    )
    foreach ($d in $defs) {
        $c = New-Card -Margin '6,0'
        $c.Cursor = 'Hand'; $c.Tag = $d.Id; $c.Padding = '16,16'
        $sp = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.Grid
        $ic = New-Object Windows.Controls.Border; $ic.Width = 34; $ic.Height = 34; $ic.CornerRadius = 8; $ic.HorizontalAlignment = 'Left'
        Set-Ref $ic ([Windows.Controls.Border]::BackgroundProperty) 'AccentSoftBrush'
        $gl = New-Glyph -Code $d.G -Brush 'AccentBrush' -Size 16; $gl.HorizontalAlignment = 'Center'; $ic.Child = $gl
        [void]$top.Children.Add($ic)
        if ($d.R) { $p = New-Pill -Text 'Recommended'; $p.HorizontalAlignment = 'Right'; $p.Margin = '0'; [void]$top.Children.Add($p) }
        [void]$sp.Children.Add($top)
        $t = New-TB -Text $d.T -Size 15 -Weight 'SemiBold'; $t.Margin = '0,12,0,2'; [void]$sp.Children.Add($t)
        [void]$sp.Children.Add((New-TB -Text $d.D -Brush 'SubTextBrush' -Size 12 -Wrap))
        $cnt = if ($d.Id -eq 'Custom') { 'You choose' } else {
            $n = @($script:AllTweaks | Where-Object { $_.Supported -and $_.Presets -contains $d.Id }).Count
            $a = @($script:AppCfg.Bloat).Count + $(if ($d.Id -eq 'Max') { @($script:AppCfg.Extra).Count } else { 0 })
            "$n tweaks$($script:Dot)up to $a apps" }
        $ct = New-TB -Text $cnt -Brush 'AccentBrush' -Size 12 -Weight 'SemiBold'; $ct.Margin = '0,10,0,0'; [void]$sp.Children.Add($ct)
        $c.Child = $sp
        $c.Add_MouseLeftButtonUp({ param($s, $e) Set-Preset $s.Tag; Show-Page 'Tweaks' })
        $script:PresetCards[$d.Id] = $c
        [void]$ui.PresetPanel.Children.Add($c)
    }
}

# ==================================================================== tweaks
function Build-TweakCards {
    $cols = @($ui.TweakCol0, $ui.TweakCol1, $ui.TweakCol2)
    foreach ($key in $script:CatDefs.Keys) {
        $def = $script:CatDefs[$key]
        $items = @($script:AllTweaks | Where-Object { (Get-CatKey $_.Category) -eq $key })
        if (-not $items.Count) { continue }
        $card = New-Card
        $sp = New-Object Windows.Controls.StackPanel
        $hdr = New-Object Windows.Controls.Grid; $hdr.Margin = '0,0,0,4'
        $hl = New-Object Windows.Controls.StackPanel; $hl.Orientation = 'Horizontal'
        [void]$hl.Children.Add((New-Glyph -Code $def.Glyph -Brush 'AccentBrush' -Size 16))
        $ht = New-TB -Text $def.Title -Size 15 -Weight 'SemiBold'; $ht.Margin = '10,0,0,0'; [void]$hl.Children.Add($ht)
        [void]$hdr.Children.Add($hl)
        $counter = New-TB -Text '' -Brush 'SubTextBrush' -Size 12; $counter.HorizontalAlignment = 'Right'; $counter.VerticalAlignment = 'Center'
        [void]$hdr.Children.Add($counter)
        [void]$sp.Children.Add($hdr)
        $rows = @()
        foreach ($t in $items) {
            $cb = New-Object Windows.Controls.CheckBox
            $cb.Style = $window.FindResource('SBCheck'); $cb.Margin = '0,12,0,0'; $cb.Tag = $t.Id
            $content = New-Object Windows.Controls.StackPanel
            [void]$content.Children.Add((New-TB -Text $t.Name -Wrap))
            $badges = New-Object Windows.Controls.WrapPanel; $badges.Margin = '0,4,0,0'
            if ($t.Reboot) { [void]$badges.Children.Add((New-Pill -Text 'Restart' -Fg 'SevWarnBrush' -Bg 'SevWarnBgBrush')) }
            if ($t.MinBuild -ge 22000) { [void]$badges.Children.Add((New-Pill -Text 'Windows 11')) }
            if ($t.Presets -contains 'Safe') { [void]$badges.Children.Add((New-Pill -Text 'Safe' -Fg 'SevOkBrush' -Bg 'SevOkBgBrush')) }
            if (-not $t.Supported) { [void]$badges.Children.Add((New-Pill -Text 'Not available on this Windows' -Fg 'SubTextBrush' -Bg 'HoverBrush')); $cb.IsEnabled = $false }
            if ($badges.Children.Count) { [void]$content.Children.Add($badges) }
            $why = New-TB -Text $t.Why -Brush 'SubTextBrush' -Size 12 -Wrap
            $why.Margin = '0,3,0,0'; $why.MaxHeight = 34; $why.TextTrimming = 'WordEllipsis'
            [void]$content.Children.Add($why)
            $cb.Content = $content
            $cb.ToolTip = $t.Why + $(if ($t.Reboot) { "`n`nNeeds a restart to take effect." } else { '' })
            $cb.Add_Checked({ Update-Summary }); $cb.Add_Unchecked({ Update-Summary })
            $script:TweakChecks[$t.Id] = $cb
            [void]$sp.Children.Add($cb)
            $rows += [pscustomobject]@{ CB = $cb; Text = "$($t.Name) $($t.Why) $($t.Category)" }
        }
        $card.Child = $sp
        [void]$cols[$def.Col].Children.Add($card)
        $script:TweakCards += [pscustomobject]@{ Card = $card; Rows = $rows; Counter = $counter }
    }
}

function Set-Preset([string]$Name) {
    $script:Preset = $Name
    $script:Suspend = $true
    foreach ($t in $script:AllTweaks) {
        $cb = $script:TweakChecks[$t.Id]
        if ($cb.IsEnabled) { $cb.IsChecked = ($Name -ne 'Custom' -and $t.Presets -contains $Name) }
    }
    $script:AppSel = @{}
    if ($Name -ne 'Custom') {
        foreach ($p in $script:AppCfg.Bloat) { $script:AppSel[$p] = $true }
        if ($Name -eq 'Max') { foreach ($p in $script:AppCfg.Extra) { $script:AppSel[$p] = $true } }
    }
    $script:Suspend = $false
    foreach ($k in $script:PresetCards.Keys) {
        $c = $script:PresetCards[$k]
        if ($k -eq $Name) { Set-Ref $c ([Windows.Controls.Border]::BorderBrushProperty) 'AccentBrush'; $c.BorderThickness = 2; $c.Padding = '15,15' }
        else { Set-Ref $c ([Windows.Controls.Border]::BorderBrushProperty) 'CardBorderBrush'; $c.BorderThickness = 1; $c.Padding = '16,16' }
    }
    foreach ($pair in @(@('Safe', $ui.BtnPresetSafe), @('Gaming', $ui.BtnPresetGaming), @('Max', $ui.BtnPresetMax))) {
        $b = $pair[1]
        if ($pair[0] -eq $Name) { Set-Ref $b ([Windows.Controls.Control]::BorderBrushProperty) 'AccentBrush'; Set-Ref $b ([Windows.Controls.Control]::ForegroundProperty) 'AccentBrush' }
        else { Set-Ref $b ([Windows.Controls.Control]::BorderBrushProperty) 'CardBorderBrush'; Set-Ref $b ([Windows.Controls.Control]::ForegroundProperty) 'TextBrush' }
    }
    Build-AppRows
    Update-Summary
}

function Update-TweakFilter {
    $q = $ui.TweakSearch.Text.Trim()
    foreach ($c in $script:TweakCards) {
        $any = $false
        foreach ($r in $c.Rows) {
            $vis = (-not $q) -or ($r.Text -like "*$q*")
            $r.CB.Visibility = if ($vis) { 'Visible' } else { 'Collapsed' }
            if ($vis) { $any = $true }
        }
        $c.Card.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }
    }
}

# ==================================================================== apps
function Get-AppMatches([string]$Pattern) {
    if ($null -eq $script:Installed) { return @() }
    return @($script:Installed | Where-Object { $_ -like $Pattern } | Where-Object { -not (Test-SBProtectedApp $_ $script:AppCfg.Protected) })
}

function Build-AppRows {
    $ui.AppsGrid.Children.Clear()
    $entries = @()
    foreach ($p in $script:AppCfg.Bloat) { $entries += [pscustomobject]@{ P = $p; Kind = 'Recommended' } }
    foreach ($p in $script:AppCfg.Extra) { $entries += [pscustomobject]@{ P = $p; Kind = 'Optional' } }
    $onlyInstalled = [bool]$ui.ChkOnlyInstalled.IsChecked
    $shown = 0; $installedCount = 0
    $sorted = $entries | Sort-Object @{ e = { if ((Get-AppMatches $_.P).Count) { 0 } else { 1 } } }, @{ e = { if ($_.Kind -eq 'Recommended') { 0 } else { 1 } } }
    foreach ($e in $sorted) {
        $m = Get-AppMatches $e.P
        $inst = $m.Count -gt 0
        if ($inst) { $installedCount++ }
        if ($onlyInstalled -and -not $inst -and $null -ne $script:Installed) { continue }
        $name = if ($script:Friendly.ContainsKey($e.P)) { $script:Friendly[$e.P] } else { ($e.P -replace '\*', '' -replace '^Microsoft\.', '' -creplace '([a-z])([A-Z])', '$1 $2').Trim() }
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Style = $window.FindResource('SBCheck'); $cb.Margin = '10,9'; $cb.Tag = $e.P
        $cb.IsChecked = [bool]$script:AppSel[$e.P]
        $sp = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.WrapPanel
        $nt = New-TB -Text $name -Weight 'SemiBold'; $nt.Margin = '0,0,8,0'; [void]$top.Children.Add($nt)
        if ($e.Kind -eq 'Recommended') { [void]$top.Children.Add((New-Pill -Text 'Recommended' -Fg 'SevOkBrush' -Bg 'SevOkBgBrush')) }
        else { [void]$top.Children.Add((New-Pill -Text 'Optional' -Fg 'SubTextBrush' -Bg 'HoverBrush')) }
        if (-not $inst -and $null -ne $script:Installed) { [void]$top.Children.Add((New-Pill -Text 'Not installed' -Fg 'SubTextBrush' -Bg 'HoverBrush')) }
        [void]$sp.Children.Add($top)
        $detail = if ($inst) { ($m | Select-Object -First 2) -join ', ' } else { $e.P }
        $dt = New-TB -Text $detail -Brush 'SubTextBrush' -Size 12; $dt.TextTrimming = 'CharacterEllipsis'; $dt.Margin = '0,2,0,0'
        [void]$sp.Children.Add($dt)
        $cb.Content = $sp
        $cb.Add_Checked({ param($s, $ev) $script:AppSel[$s.Tag] = $true; Update-Summary })
        $cb.Add_Unchecked({ param($s, $ev) $script:AppSel[$s.Tag] = $false; Update-Summary })
        [void]$ui.AppsGrid.Children.Add($cb)
        $shown++
    }
    if ($null -eq $script:Installed) { $ui.AppsStatus.Text = 'Looking for installed apps...' }
    else { $ui.AppsStatus.Text = "$(Get-Plural $installedCount 'removable app') found on this PC" }
    if ($shown -eq 0) {
        $t = New-TB -Text "No removable bloat apps are installed$($script:Dash)nice and clean." -Brush 'SubTextBrush'; $t.Margin = '10,12'
        [void]$ui.AppsGrid.Children.Add($t)
    }
}

function Get-SelectedApps {
    $sel = @($script:AppSel.Keys | Where-Object { $script:AppSel[$_] })
    if ($null -ne $script:Installed) { $sel = @($sel | Where-Object { (Get-AppMatches $_).Count -gt 0 }) }
    return $sel
}

# ==================================================================== summary
function Update-Summary {
    if ($script:Suspend) { return }
    $ids = @($script:TweakChecks.Keys | Where-Object { $script:TweakChecks[$_].IsChecked })
    $apps = @(Get-SelectedApps)
    $sel = @($script:AllTweaks | Where-Object { $ids -contains $_.Id })
    $reboot = @($sel | Where-Object Reboot).Count
    $ui.NavTweaksCount.Text = "$($ids.Count)"
    $ui.NavAppsCount.Text = "$($apps.Count)"
    $ui.SumTweaks.Text = "$($ids.Count)"; $ui.SumApps.Text = "$($apps.Count)"; $ui.SumRestart.Text = "$reboot"
    $ui.SumList.Text = if ($sel.Count) { ($sel | ForEach-Object { $_.Name }) -join $script:Dot } else { 'Nothing selected yet. Pick a preset on the Overview page or tick tweaks.' }
    $ui.FooterSummary.Text = if ($ids.Count -or $apps.Count) { "$(Get-Plural $ids.Count 'tweak') and $(Get-Plural $apps.Count 'app') selected$($script:Dash)nothing changes until you press Apply" } else { 'Nothing selected yet' }
    foreach ($c in $script:TweakCards) {
        $on = @($c.Rows | Where-Object { $_.CB.IsChecked }).Count
        $c.Counter.Text = "$on of $($c.Rows.Count)"
    }
}

# ==================================================================== apply
$script:ApplyWork = {
    param($Root, $Ids, $Apps, $Opts)
    . "$Root\lib\Core.ps1"; . "$Root\lib\Tweaks.ps1"; . "$Root\lib\Analyze.ps1"
    $cfg = Get-Content -LiteralPath "$Root\config\apps.json" -Raw | ConvertFrom-Json
    $tweaks = @(Get-SBTweaks | Where-Object { $_.Supported -and $Ids -contains $_.Id })
    Start-SBSession -Preset $Opts.Preset -DryRun:$Opts.DryRun
    $total = $tweaks.Count + @($Apps).Count; $i = 0
    if (-not $Opts.DryRun) {
        try { Get-SBSnapshot | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:SB.SessionDir 'before.json') -Encoding UTF8 } catch { }
        if ($Opts.RestorePoint -and -not (New-SBRestorePoint) -and -not $Opts.ContinueWithoutRP) {
            return [pscustomobject]@{ Status = 'NoRestorePoint'; SessionDir = $script:SB.SessionDir }
        }
    }
    foreach ($t in $tweaks) {
        try { Invoke-SBTweak -Tweak $t } catch { Write-SBLog "Tweak $($t.Id) skipped: $($_.Exception.Message)" 'ERR'; $script:SB.Stats.Failed++ }
        $i++; $global:SBLogQueue.Enqueue("@@P $i $total")
    }
    if (@($Apps).Count) {
        Write-SBLog 'Removing apps' 'STEP'
        foreach ($p in $Apps) {
            try { Remove-SBApp -Pattern $p -Protected $cfg.Protected -AllUsers:([bool]$Opts.AllUsers) -TweakId 'apps' } catch { Write-SBLog "App $p skipped: $($_.Exception.Message)" 'WARN' }
            $i++; $global:SBLogQueue.Enqueue("@@P $i $total")
        }
    }
    Save-SBSession
    return [pscustomobject]@{ Status = 'Done'; Stats = $script:SB.Stats.Clone(); SessionDir = $script:SB.SessionDir; DryRun = [bool]$Opts.DryRun
                              Reboot = [bool]@($tweaks | Where-Object Reboot).Count }
}

function Set-Busy([bool]$On) {
    $script:Busy = $On
    $ui.BtnApply.IsEnabled = -not $On
    foreach ($p in 'Overview','Tweaks','Apps','Undo') { $ui["Nav$p"].IsEnabled = -not $On }
    $ui.BtnBack.IsEnabled = -not $On
}

function Start-Apply([switch]$ContinueWithoutRP, [switch]$NoConfirm) {
    $ids = @($script:TweakChecks.Keys | Where-Object { $script:TweakChecks[$_].IsChecked })
    $apps = @(Get-SelectedApps)
    if (-not $ids.Count -and -not $apps.Count) {
        [void][Windows.MessageBox]::Show($window, 'Nothing is selected yet. Pick a preset or tick some tweaks first.', 'SafeBoost', 'OK', 'Information'); return
    }
    $dry = [bool]$ui.ChkDryRun.IsChecked
    if (-not $dry -and -not $NoConfirm -and -not $ContinueWithoutRP) {
        $msg = "Apply $($ids.Count) tweaks and remove $($apps.Count) apps?`n`nEvery change is backed up first and can be undone from 'Backups & undo'."
        if ([Windows.MessageBox]::Show($window, $msg, 'SafeBoost', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    $script:LogTarget = 'apply'
    if (-not $ContinueWithoutRP) { $ui.LogPanel.Children.Clear() }
    $ui.ApplyProgress.Value = 0
    $ui.BtnRestart.Visibility = 'Collapsed'; $ui.BtnOpenBackup.Visibility = 'Collapsed'
    $ui.ApplyStatus.Text = if ($dry) { 'Previewing...' } elseif ($ui.ChkRestorePoint.IsChecked -and -not $ContinueWithoutRP) { 'Creating a restore point (about a minute)...' } else { 'Working...' }
    Set-Busy $true
    $opts = @{ Preset = $script:Preset; DryRun = $dry; RestorePoint = [bool]$ui.ChkRestorePoint.IsChecked; AllUsers = [bool]$ui.ChkAllUsers.IsChecked; ContinueWithoutRP = [bool]$ContinueWithoutRP }
    Start-SBBackground -Work $script:ApplyWork.ToString() -Arguments @($script:Root, $ids, $apps, $opts) -OnComplete { param($r, $err) Complete-Apply $r $err }
}

function Complete-Apply($r, $err) {
    $r = @($r)[-1]
    Set-Busy $false
    if ($err -or -not $r) {
        $ui.ApplyStatus.Text = "Stopped: $err"
        Add-LogLine "[--:--:--] [ERR ] $err"
        return
    }
    if ($r.Status -eq 'NoRestorePoint') {
        $ui.ApplyStatus.Text = 'Restore point could not be created.'
        $q = "Windows could not create a System Restore point (System Protection may be turned off).`n`nSafeBoost still saves its own backup of every value it changes, so Undo will work.`n`nContinue without a restore point?"
        if ([Windows.MessageBox]::Show($window, $q, 'SafeBoost', 'YesNo', 'Warning') -eq 'Yes') { Start-Apply -ContinueWithoutRP }
        else { $ui.ApplyStatus.Text = 'Cancelled - nothing was changed.' }
        return
    }
    $s = $r.Stats
    $ui.ApplyProgress.Value = 100
    $script:LastSession = $r.SessionDir
    $ui.BtnOpenBackup.Visibility = 'Visible'
    if ($r.DryRun) {
        $ui.ApplyStatus.Text = "Preview finished$($script:Dash)nothing was changed. Untick 'Preview only' to apply for real."
    } else {
        $ui.ApplyStatus.Text = "Done: $($s.Applied) changed, $($s.Skipped) already set, $($s.Failed) failed." + $(if ($r.Reboot) { ' Restart to finish.' } else { '' })
        if ($r.Reboot -or $s.Applied) { $ui.BtnRestart.Visibility = 'Visible' }
    }
}

# ==================================================================== undo
function Update-Runs {
    $ui.RunsPanel.Children.Clear()
    $runs = @(Get-SBRuns -IncludeUndone)
    if (-not $runs.Count) {
        $c = New-Card
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        [void]$sp.Children.Add((New-Glyph -Code 0xE946 -Brush 'AccentBrush' -Size 16))
        $t = New-TB -Text 'No SafeBoost runs yet. Backups will appear here after you apply changes.' -Brush 'SubTextBrush'; $t.Margin = '10,0,0,0'
        [void]$sp.Children.Add($t); $c.Child = $sp
        [void]$ui.RunsPanel.Children.Add($c); return
    }
    foreach ($r in $runs) {
        $c = New-Card -Margin '0,0,0,10'
        $g = New-Object Windows.Controls.Grid
        foreach ($w in 44, -1, -2, -2) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if ($w -eq -1) { New-Object Windows.GridLength 1, 'Star' } elseif ($w -eq -2) { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength $w }
            $g.ColumnDefinitions.Add($cd)
        }
        [void]$g.Children.Add((New-Glyph -Code 0xE81C -Brush $(if ($r.Undone) { 'SubTextBrush' } else { 'AccentBrush' }) -Size 18))
        $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
        [void]$sp.Children.Add((New-TB -Text "$($r.Preset) preset" -Weight 'SemiBold'))
        $when = if ($r.Date) { $r.Date.ToString('MMM d, yyyy  h:mm tt') } else { $r.Name }
        [void]$sp.Children.Add((New-TB -Text "$when$($script:Dot)$(Get-Plural $r.Count 'change')$(if ($r.Apps) { "$($script:Dot)$(Get-Plural $r.Apps 'app') removed" })" -Brush 'SubTextBrush' -Size 12))
        [void]$g.Children.Add($sp)
        $pill = if ($r.Undone) { New-Pill -Text 'Undone' -Fg 'SubTextBrush' -Bg 'HoverBrush' } else { New-Pill -Text 'Active' -Fg 'SevOkBrush' -Bg 'SevOkBgBrush' }
        $pill.Margin = '0,0,14,0'; [Windows.Controls.Grid]::SetColumn($pill, 2); [void]$g.Children.Add($pill)
        $b = New-Object Windows.Controls.Button; $b.Style = $window.FindResource('BtnBase'); $b.Content = 'Undo'; $b.Tag = $r.Name; $b.MinWidth = 84
        $b.IsEnabled = -not $r.Undone
        [Windows.Controls.Grid]::SetColumn($b, 3)
        $b.Add_Click({ param($s, $e) Start-Undo $s.Tag })
        [void]$g.Children.Add($b)
        $c.Child = $g
        [void]$ui.RunsPanel.Children.Add($c)
    }
}

function Start-Undo([string]$Session) {
    $active = @(Get-SBRuns)
    $idx = [array]::IndexOf(@($active | ForEach-Object { $_.Name }), $Session)
    $extra = if ($idx -gt 0) { "`n`nThe $idx newer run(s) will be undone first so nothing is restored out of order." } else { '' }
    if ([Windows.MessageBox]::Show($window, "Restore every setting changed by this run to its previous value?$extra", 'SafeBoost', 'YesNo', 'Question') -ne 'Yes') { return }
    $script:LogTarget = 'undo'
    $ui.UndoLogPanel.Children.Clear(); $ui.UndoLogCard.Visibility = 'Visible'
    $ui.UndoStatus.Text = 'Undoing...'
    Set-Busy $true
    $work = {
        param($Root, $Session)
        . "$Root\lib\Core.ps1"
        $script:SB.LogFile = Join-Path $script:SB.Root ('undo-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Invoke-SBUndoRun -Session $Session
    }
    Start-SBBackground -Work $work.ToString() -Arguments @($script:Root, $Session) -OnComplete {
        param($r, $err)
        $r = @($r)[-1]
        Set-Busy $false
        if ($err) { $ui.UndoStatus.Text = "Undo error: $err" }
        elseif ($r.Failed) { $ui.UndoStatus.Text = "Undo finished, $($r.Failed) item(s) need manual restore (see .reg files in the backup folder)." }
        else { $ui.UndoStatus.Text = 'Undo complete. Restart your PC to finish. Removed apps can be reinstalled from the Microsoft Store.' }
        Update-Runs
    }
}

# ==================================================================== wire up events
$ui.BtnMin.Add_Click({ $window.WindowState = 'Minimized' })
$ui.BtnMax.Add_Click({ $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
$ui.BtnClose.Add_Click({ $window.Close() })
$ui.BtnTheme.Add_Click({ Set-SBTheme $(if ($script:ThemeName -eq 'Dark') { 'Light' } else { 'Dark' }) })
$window.Add_StateChanged({
    if ($window.WindowState -eq 'Maximized') { $ui.RootBorder.Margin = '7'; $ui.GlyphMax.Text = [string][char]0xE923 }
    else { $ui.RootBorder.Margin = '0'; $ui.GlyphMax.Text = [string][char]0xE922 }
})
$window.Add_Closing({
    param($s, $e)
    if ($script:Busy) {
        if ([Windows.MessageBox]::Show($window, 'SafeBoost is still working. Closing now could leave a run half-finished (it can still be undone). Close anyway?', 'SafeBoost', 'YesNo', 'Warning') -ne 'Yes') { $e.Cancel = $true }
    }
})

foreach ($p in $script:Pages) {
    $ui["Nav$p"].Tag = $p
    $ui["Nav$p"].Add_Checked({ param($s, $e) if ($script:CurrentPage -ne $s.Tag) { Show-Page $s.Tag } })
}
$ui.BtnNext.Add_Click({ $i = [array]::IndexOf($script:Pages, $script:CurrentPage); if ($i -lt 3) { Show-Page $script:Pages[$i + 1] } })
$ui.BtnBack.Add_Click({ $i = [array]::IndexOf($script:Pages, $script:CurrentPage); if ($i -gt 0) { Show-Page $script:Pages[[math]::Min($i - 1, 3)] } })

$ui.BtnPresetSafe.Add_Click({ Set-Preset 'Safe' })
$ui.BtnPresetGaming.Add_Click({ Set-Preset 'Gaming' })
$ui.BtnPresetMax.Add_Click({ Set-Preset 'Max' })
$ui.BtnClear.Add_Click({ Set-Preset 'Custom' })
$ui.TweakSearch.Add_TextChanged({ Update-TweakFilter })

$ui.BtnAppsRecommended.Add_Click({ $script:AppSel = @{}; foreach ($p in $script:AppCfg.Bloat) { $script:AppSel[$p] = $true }; Build-AppRows; Update-Summary })
$ui.BtnAppsAll.Add_Click({ $script:AppSel = @{}; foreach ($p in @($script:AppCfg.Bloat) + @($script:AppCfg.Extra)) { $script:AppSel[$p] = $true }; Build-AppRows; Update-Summary })
$ui.BtnAppsNone.Add_Click({ $script:AppSel = @{}; Build-AppRows; Update-Summary })
$ui.ChkOnlyInstalled.Add_Checked({ Build-AppRows }); $ui.ChkOnlyInstalled.Add_Unchecked({ Build-AppRows })

$ui.ChkDryRun.Add_Checked({ $ui.BtnApplyText.Text = 'Preview changes'; $ui.BadgeDryRun.Visibility = 'Visible' })
$ui.ChkDryRun.Add_Unchecked({ $ui.BtnApplyText.Text = 'Apply changes'; $ui.BadgeDryRun.Visibility = 'Collapsed' })
$ui.BtnApply.Add_Click({ Start-Apply })
$ui.BtnRestart.Add_Click({
    if ([Windows.MessageBox]::Show($window, 'Restart the PC now? Save your work in other apps first.', 'SafeBoost', 'YesNo', 'Question') -eq 'Yes') { Restart-Computer -Force }
})
$openFolder = { param($path) if ($path -and (Test-Path -LiteralPath $path)) { Start-Process explorer.exe -ArgumentList "`"$path`"" } }
$ui.BtnOpenBackup.Add_Click({ & $openFolder $script:LastSession })
$ui.BtnUndoFolder.Add_Click({ $d = Join-Path $script:SB.Root 'backups'; New-Item -ItemType Directory -Path $d -Force | Out-Null; & $openFolder $d })
$ui.BtnSystemRestore.Add_Click({ Start-Process rstrui.exe })
$ui.BtnUndoRefresh.Add_Click({ Update-Runs })

# ==================================================================== build
Build-PresetCards
Build-TweakCards
Set-Preset 'Gaming'
Show-Page 'Overview'
$themeToUse = if ($Theme -eq 'System') { Get-SystemTheme } else { $Theme }
Set-SBTheme $themeToUse

# ==================================================================== screenshot mode
function Save-SBRender([string]$Path) {
    $window.UpdateLayout()
    $window.Dispatcher.Invoke([action]{ }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $el = $ui.RootBorder
    # Lay out at a fixed size so images don't depend on the capture machine's screen resolution.
    $el.Measure((New-Object Windows.Size 1240, 800))
    $el.Arrange((New-Object Windows.Rect 0, 0, 1240, 800))
    if ($env:GITHUB_ACTIONS) { Write-Host "::notice::Render $([IO.Path]::GetFileName($Path)): $($el.ActualWidth) x $($el.ActualHeight)" }
    $scale = 1.5
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int](1240 * $scale)), ([int](800 * $scale)), (96 * $scale), (96 * $scale), ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($el)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } catch { Write-Host "::error::Saving $Path failed: $($_.Exception.Message)" } finally { $fs.Close() }
    Write-Host "Saved $Path"
}

if ($Screenshot) {
    New-Item -ItemType Directory -Path $Screenshot -Force | Out-Null
    $global:SBLogQueue = $script:LogQueue
    Show-Overview (Get-SBSystemInfo) (Get-SBFindings)
    $script:Installed = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Build-AppRows; Update-Summary
    # A real dry run so the activity log shows genuine output
    $ui.ChkDryRun.IsChecked = $true
    $ids = @($script:TweakChecks.Keys | Where-Object { $script:TweakChecks[$_].IsChecked })
    $r = & $script:ApplyWork $script:Root $ids @() @{ Preset = 'Gaming'; DryRun = $true }
    Invoke-Pump
    Complete-Apply @($r)[-1] $null
    if ($env:SAFEBOOST_CI -eq '1') {
        # Disposable test machine only: make two real runs so the Backups page shows real history.
        $safeIds = @($script:AllTweaks | Where-Object { $_.Supported -and $_.Presets -contains 'Safe' } | ForEach-Object { $_.Id })
        [void](& $script:ApplyWork $script:Root $safeIds @() @{ Preset = 'Safe'; DryRun = $false; RestorePoint = $false })
        [void](& $script:ApplyWork $script:Root $ids @() @{ Preset = 'Gaming'; DryRun = $false; RestorePoint = $false })
        $line = $null; while ($script:LogQueue.TryDequeue([ref]$line)) { }
    }
    $ui.ChkDryRun.IsChecked = $false
    $global:SBLogQueue = $script:LogQueue

    $window.WindowStartupLocation = 'Manual'; $window.Left = 0; $window.Top = 0
    $window.Width = 1240; $window.Height = 800
    $window.ShowInTaskbar = $false; $window.ShowActivated = $false
    try { $window.Show() } catch { Write-Host "::warning::Window.Show failed: $($_.Exception.Message)" }
    foreach ($th in 'Dark', 'Light') {
        Set-SBTheme $th
        foreach ($pg in $script:Pages) {
            Show-Page $pg
            if ($pg -eq 'Apply') { $ui.LogScroll.ScrollToHome() }
            Save-SBRender (Join-Path $Screenshot ("{0}-{1}.png" -f $pg.ToLower(), $th.ToLower()))
        }
    }
    $window.Close()
    exit 0
}

# ==================================================================== run
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(100)
$timer.Add_Tick({ Invoke-Pump })
$timer.Start()

Start-SBBackground -Work {
    param($Root)
    . "$Root\lib\Core.ps1"; . "$Root\lib\Analyze.ps1"
    [pscustomobject]@{ Info = Get-SBSystemInfo; Findings = @(Get-SBFindings) }
}.ToString() -Arguments @($script:Root) -OnComplete {
    param($r, $err)
    $r = @($r)[-1]
    if ($r) { Show-Overview $r.Info $r.Findings } else { $ui.HealthStatus.Text = "Scan failed: $err" }
}

Start-SBBackground -Work {
    @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}.ToString() -Arguments @() -OnComplete {
    param($r, $err)
    $script:Installed = @($r)
    Build-AppRows; Update-Summary
}

try {
    [void]$window.ShowDialog()
} catch {
    $msg = "SafeBoost hit an unexpected error:`n`n$($_.Exception.Message)"
    try { Add-Content -LiteralPath (Join-Path $script:SB.Root 'gui-error.log') -Value "$(Get-Date -Format o) $($_ | Out-String)" } catch { }
    [void][Windows.MessageBox]::Show($msg, 'SafeBoost', 'OK', 'Error')
}
