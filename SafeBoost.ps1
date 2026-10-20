<#
.SYNOPSIS
    SafeBoost - safe, fully reversible Windows 10/11 debloat + gaming performance tool.

.DESCRIPTION
    Every change is backed up first (System Restore point + per-value JSON backup + .reg exports)
    and can be undone with Undo.bat / Restore.ps1. Nothing that Windows needs to boot, update,
    stay secure or run games is ever removed or disabled.

.EXAMPLE
    .\SafeBoost.ps1                      # interactive menu
    .\SafeBoost.ps1 -Analyze             # read-only PC check
    .\SafeBoost.ps1 -Preset Gaming -DryRun
    .\SafeBoost.ps1 -Preset Gaming -Silent
    .\SafeBoost.ps1 -Preset Custom -Only gamedvr,hags,powerplan
#>
[CmdletBinding()]
param(
    [ValidateSet('Safe','Gaming','Max','Custom')][string]$Preset,
    [switch]$DryRun,
    [switch]$Silent,
    [switch]$Analyze,
    [switch]$ListTweaks,
    [string[]]$Only,
    [string[]]$Exclude,
    [switch]$NoAppRemoval,
    [switch]$AllUsersApps,
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- environment guards
if ($PSVersionTable.PSEdition -eq 'Core') {
    # Appx + System Restore cmdlets only work properly in Windows PowerShell 5.1
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value) { $argList += "-$($kv.Key)" } }
        elseif ($kv.Value -is [array]) { $argList += "-$($kv.Key)"; $argList += ($kv.Value -join ',') }
        else { $argList += "-$($kv.Key)"; $argList += "$($kv.Value)" }
    }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @argList
    exit $LASTEXITCODE
}

. "$PSScriptRoot\lib\Core.ps1"
. "$PSScriptRoot\lib\Tweaks.ps1"
. "$PSScriptRoot\lib\Analyze.ps1"

if (-not (Test-SBAdmin)) {
    Write-Host 'SafeBoost needs to run as Administrator. Double-click Run.bat (it asks for admin automatically).' -ForegroundColor Red
    if (-not $Silent) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}

$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -ne 1 -and $env:SAFEBOOST_CI -ne '1') {
    # (SAFEBOOST_CI is only set by the automated test pipeline, whose test machines run Windows Server)
    Write-Host 'This is Windows Server - SafeBoost only supports Windows 10/11 desktop editions.' -ForegroundColor Red
    if ($env:GITHUB_ACTIONS) { Write-Host '::error::Blocked: Windows Server detected' }
    exit 1
}
$build = Get-SBWindowsBuild
if ($build -lt 19041) {
    Write-Host "Windows build $build is very old (before Windows 10 2004). SafeBoost is only tested on 19041+." -ForegroundColor Red
    if ($Silent -or (Read-Host 'Continue anyway? (type YES)') -ne 'YES') { exit 1 }
}

$appCfg = Get-Content -LiteralPath "$PSScriptRoot\config\apps.json" -Raw | ConvertFrom-Json

# ---------------------------------------------------------------- helpers
function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '   ____         __      ____                    _   ' -ForegroundColor Cyan
    Write-Host '  / ___|  __ _ / _| ___| __ )  ___   ___  ___| |_ ' -ForegroundColor Cyan
    Write-Host '  \___ \ / _` | |_ / _ \  _ \ / _ \ / _ \/ __| __|' -ForegroundColor Cyan
    Write-Host '   ___) | (_| |  _|  __/ |_) | (_) | (_) \__ \ |_ ' -ForegroundColor Cyan
    Write-Host '  |____/ \__,_|_|  \___|____/ \___/ \___/|___/\__|' -ForegroundColor Cyan
    Write-Host "  v$script:SBVersion  |  Windows build $build  |  every change is reversible" -ForegroundColor DarkGray
    Write-Host ''
}

function Test-SBUserMismatch {
    # If a standard user elevated with a DIFFERENT admin account, HKCU tweaks would land on the wrong account.
    $console = (Get-CimInstance Win32_ComputerSystem).UserName
    if ($console -and ($console.Split('\')[-1] -ne $env:USERNAME)) {
        Write-SBLog "You are signed in as '$console' but SafeBoost runs as '$env:USERNAME'. Per-user tweaks will apply to '$env:USERNAME', not you." 'WARN'
        if ($Silent) { return $true }
        return ((Read-Host 'Continue anyway? (y/N)') -match '^[yY]')
    }
    return $true
}

function Test-SBPendingReboot {
    return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
           (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Select-SBCustom {
    $all = @(Get-SBTweaks | Where-Object Supported)
    $picked = @{}
    foreach ($t in $all) { $picked[$t.Id] = ($t.Presets -contains 'Gaming') }
    $removeApps = $true
    while ($true) {
        Write-Banner
        Write-Host '  CUSTOM - type numbers to toggle (e.g. 3 7 12), A = apply, Q = back' -ForegroundColor Yellow
        Write-Host ''
        $i = 0
        foreach ($t in $all) {
            $i++
            $mark = if ($picked[$t.Id]) { '[x]' } else { '[ ]' }
            Write-Host ('  {0,2}. {1} {2,-14} {3}' -f $i, $mark, $t.Category, $t.Name) -ForegroundColor $(if ($picked[$t.Id]) { 'White' } else { 'DarkGray' })
        }
        $appMark = if ($removeApps) { '[x]' } else { '[ ]' }
        Write-Host ('  {0,2}. {1} {2,-14} {3}' -f 0, $appMark, 'Apps', 'Remove bloat apps (Bloat list)')
        Write-Host ''
        $in = Read-Host '  Choice'
        if ($in -match '^[qQ]') { return $null }
        if ($in -match '^[aA]') { return [pscustomobject]@{ Tweaks = @($all | Where-Object { $picked[$_.Id] }); Apps = $removeApps } }
        foreach ($n in ($in -split '[\s,]+' | Where-Object { $_ -match '^\d+$' })) {
            $n = [int]$n
            if ($n -eq 0) { $removeApps = -not $removeApps }
            elseif ($n -ge 1 -and $n -le $all.Count) { $id = $all[$n - 1].Id; $picked[$id] = -not $picked[$id] }
        }
    }
}

function Invoke-SBRun {
    param([string]$Name, [object[]]$Tweaks, [string[]]$AppPatterns, [switch]$IsDryRun)

    Write-Host ''
    Write-Host "  Plan: $Name $(if ($IsDryRun) { '(DRY RUN - nothing will change)' })" -ForegroundColor Yellow
    foreach ($t in $Tweaks) {
        Write-Host ("   + {0}{1}" -f $t.Name, $(if ($t.Reboot) { '  (restart needed)' })) -ForegroundColor White
        Write-Host ("       {0}" -f $t.Why) -ForegroundColor DarkGray
    }
    if ($AppPatterns.Count) { Write-Host "   + Remove up to $($AppPatterns.Count) bloat app patterns (only those actually installed)$(if ($AllUsersApps) { ' for ALL users' })" -ForegroundColor White }
    Write-Host ''
    if (-not $Silent -and -not $IsDryRun) {
        if ((Read-Host '  Apply these changes? (y/N)') -notmatch '^[yY]') { Write-Host '  Cancelled - nothing changed.' -ForegroundColor DarkGray; return }
    }
    if (-not $IsDryRun -and -not (Test-SBUserMismatch)) { return }

    Start-SBSession -Preset $Name -DryRun:$IsDryRun
    if (-not $IsDryRun) {
        Get-SBSnapshot | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:SB.SessionDir 'before.json') -Encoding UTF8
        if (Test-SBPendingReboot) { Write-SBLog 'Windows has a pending restart from updates. Restarting first is recommended (not required).' 'WARN' }

        if ($SkipRestorePoint) {
            Write-SBLog 'Restore point skipped by request (-SkipRestorePoint). JSON/.reg backups are still made.' 'WARN'
        } elseif (-not (New-SBRestorePoint)) {
            Write-SBLog 'No restore point. SafeBoost still keeps its own backup of every value it changes, so Undo.bat works either way.' 'WARN'
            if ($Silent) { Write-SBLog 'Silent mode: stopping because the restore point failed. Re-run with -SkipRestorePoint to proceed anyway.' 'ERR'; return }
            if ((Read-Host '  Continue WITHOUT a restore point? (y/N)') -notmatch '^[yY]') { Write-SBLog 'Stopped - nothing changed.' 'INFO'; return }
        }
    }

    foreach ($t in $Tweaks) {
        try { Invoke-SBTweak -Tweak $t }
        catch { Write-SBLog "Tweak $($t.Id) hit an error and was skipped: $($_.Exception.Message)" 'ERR'; $script:SB.Stats.Failed++ }
    }
    if ($AppPatterns.Count) {
        Write-SBLog 'Removing bloat apps' 'STEP'
        foreach ($p in $AppPatterns) {
            try { Remove-SBApp -Pattern $p -Protected $appCfg.Protected -AllUsers:$AllUsersApps -TweakId 'apps' }
            catch { Write-SBLog "App $p skipped: $($_.Exception.Message)" 'WARN' }
        }
    }
    Save-SBSession

    $s = $script:SB.Stats
    Write-Host ''
    Write-Host '  =========================================' -ForegroundColor Cyan
    if ($IsDryRun) {
        Write-Host '  DRY RUN finished - nothing was changed.' -ForegroundColor Cyan
    } else {
        Write-Host ("  Done. {0} changed, {1} already OK, {2} failed." -f $s.Applied, $s.Skipped, $s.Failed) -ForegroundColor Green
        Write-Host "  Backup + log: $($script:SB.SessionDir)" -ForegroundColor DarkGray
        Write-Host '  Undo any time: double-click Undo.bat' -ForegroundColor DarkGray
    }
    Write-Host '  =========================================' -ForegroundColor Cyan
    if (-not $IsDryRun -and -not $Silent) {
        if ((Read-Host '  Restart now so everything takes effect? (y/N)') -match '^[yY]') { Restart-Computer -Force }
        else { Write-Host '  OK - restart later when convenient.' -ForegroundColor DarkGray }
    }
}

function Get-SBPresetPlan([string]$Name) {
    $tweaks = Get-SBTweaks -Preset $Name
    $apps = @()
    if (-not $NoAppRemoval) {
        $apps = @($appCfg.Bloat)
        if ($Name -eq 'Max') { $apps += @($appCfg.Extra) }
    }
    if ($Only)    { $tweaks = @($tweaks | Where-Object { $Only -contains $_.Id }) }
    if ($Exclude) { $tweaks = @($tweaks | Where-Object { $Exclude -notcontains $_.Id }); if ($Exclude -contains 'apps') { $apps = @() } }
    return [pscustomobject]@{ Tweaks = $tweaks; Apps = $apps }
}

# ---------------------------------------------------------------- command-line mode
if ($ListTweaks) {
    Get-SBTweaks | Sort-Object Category | Format-Table Id, Category, @{n='Presets';e={$_.Presets -join ','}}, Supported, Name -AutoSize
    exit 0
}
if ($Analyze) { Show-SBReport -SaveTo (Join-Path $env:TEMP 'SafeBoost-report.txt'); exit 0 }
if ($Preset) {
    if ($Preset -eq 'Custom') {
        if (-not $Only) { Write-Host 'Custom preset needs -Only id1,id2 (see -ListTweaks)' -ForegroundColor Red; exit 1 }
        $tw = @(Get-SBTweaks | Where-Object { $_.Supported -and $Only -contains $_.Id })
        $apps = if ($Only -contains 'apps') { @($appCfg.Bloat) } else { @() }
        Invoke-SBRun -Name 'Custom' -Tweaks $tw -AppPatterns $apps -IsDryRun:$DryRun
    } else {
        $plan = Get-SBPresetPlan $Preset
        Invoke-SBRun -Name $Preset -Tweaks $plan.Tweaks -AppPatterns $plan.Apps -IsDryRun:$DryRun
    }
    exit 0
}

# ---------------------------------------------------------------- interactive menu
while ($true) {
    Write-Banner
    Write-Host '  1  Check my PC (read-only - finds the REAL FPS problems)' -ForegroundColor White
    Write-Host '  2  SAFE     debloat + privacy + cleanup            (any PC)' -ForegroundColor Green
    Write-Host '  3  GAMING   Safe + FPS / latency tweaks            (recommended for gaming)' -ForegroundColor Green
    Write-Host '  4  MAX      Gaming + lean visuals + extra app removal (low-end PCs)' -ForegroundColor Yellow
    Write-Host '  5  CUSTOM   choose every tweak yourself' -ForegroundColor White
    Write-Host '  6  PREVIEW  dry-run a preset (shows what would change)' -ForegroundColor Cyan
    Write-Host '  7  UNDO     restore a previous SafeBoost run' -ForegroundColor Magenta
    Write-Host '  Q  Quit'
    Write-Host ''
    switch ((Read-Host '  Choose').Trim().ToUpper()) {
        '1' { Show-SBReport -SaveTo (Join-Path $env:TEMP 'SafeBoost-report.txt'); Read-Host '  Press Enter' | Out-Null }
        '2' { $p = Get-SBPresetPlan 'Safe';   Invoke-SBRun -Name 'Safe'   -Tweaks $p.Tweaks -AppPatterns $p.Apps; Read-Host '  Press Enter' | Out-Null }
        '3' { $p = Get-SBPresetPlan 'Gaming'; Invoke-SBRun -Name 'Gaming' -Tweaks $p.Tweaks -AppPatterns $p.Apps; Read-Host '  Press Enter' | Out-Null }
        '4' { $p = Get-SBPresetPlan 'Max';    Invoke-SBRun -Name 'Max'    -Tweaks $p.Tweaks -AppPatterns $p.Apps; Read-Host '  Press Enter' | Out-Null }
        '5' {
            $c = Select-SBCustom
            if ($c) { Invoke-SBRun -Name 'Custom' -Tweaks $c.Tweaks -AppPatterns $(if ($c.Apps -and -not $NoAppRemoval) { @($appCfg.Bloat) } else { @() }); Read-Host '  Press Enter' | Out-Null }
        }
        '6' {
            $which = Read-Host '  Preview which preset? (Safe/Gaming/Max)'
            if ($which -in 'Safe','Gaming','Max') { $p = Get-SBPresetPlan $which; Invoke-SBRun -Name $which -Tweaks $p.Tweaks -AppPatterns $p.Apps -IsDryRun; Read-Host '  Press Enter' | Out-Null }
        }
        '7' { & "$PSScriptRoot\Restore.ps1"; Read-Host '  Press Enter' | Out-Null }
        'Q' { exit 0 }
    }
}
