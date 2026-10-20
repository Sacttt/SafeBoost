<#
.SYNOPSIS
    Undo SafeBoost changes using the backups it recorded.

.EXAMPLE
    .\Restore.ps1                 # pick a run from a list
    .\Restore.ps1 -Latest -Silent # undo the most recent run without prompts
    .\Restore.ps1 -Session 20261020-124500
    .\Restore.ps1 -All            # undo EVERY SafeBoost run, newest first
#>
[CmdletBinding()]
param(
    [string]$Session,
    [switch]$Latest,
    [switch]$All,
    [switch]$Silent
)

if ($PSVersionTable.PSEdition -eq 'Core') {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Session) { $a += '-Session', $Session }; if ($Latest) { $a += '-Latest' }; if ($All) { $a += '-All' }; if ($Silent) { $a += '-Silent' }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @a
    exit $LASTEXITCODE
}

. "$PSScriptRoot\lib\Core.ps1"

if (-not (Test-SBAdmin)) { Write-Host 'Run as Administrator (use Undo.bat).' -ForegroundColor Red; exit 1 }

$runs = @(Get-SBRuns)
if ($runs.Count -eq 0) {
    Write-Host 'No SafeBoost runs to undo.' -ForegroundColor Yellow
    Write-Host 'You can still use Windows System Restore: press Win+R, type rstrui, pick a "SafeBoost" restore point.' -ForegroundColor DarkGray
    exit 0
}

$target = $null
if ($All)         { $target = $runs[-1].Name }
elseif ($Latest)  { $target = $runs[0].Name }
elseif ($Session) { if (-not ($runs | Where-Object Name -eq $Session)) { Write-Host "Run $Session not found (or already undone)." -ForegroundColor Red; exit 1 }; $target = $Session }
else {
    Write-Host ''
    Write-Host '  SafeBoost runs you can undo (newest first):' -ForegroundColor Cyan
    for ($i = 0; $i -lt $runs.Count; $i++) {
        Write-Host ('  {0,2}. {1}  preset: {2,-7} changes: {3}' -f ($i + 1), $runs[$i].Name, $runs[$i].Preset, $runs[$i].Count)
    }
    Write-Host '   A. Undo ALL of them'
    Write-Host ''
    $in = Read-Host '  Which one? (number / A / Enter to cancel)'
    if (-not $in) { exit 0 }
    if ($in -match '^[aA]$') { $target = $runs[-1].Name }
    elseif ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $runs.Count) {
        $target = $runs[[int]$in - 1].Name
        if ([int]$in -gt 1) { Write-Host "  Note: the $([int]$in - 1) newer run(s) will be undone first so nothing is left half-restored." -ForegroundColor Yellow }
    } else { exit 0 }
}

if (-not $Silent) {
    if ((Read-Host '  Undo now? (y/N)') -notmatch '^[yY]') { exit 0 }
}

$script:SB.LogFile = Join-Path $script:SB.Root ('undo-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$result = Invoke-SBUndoRun -Session $target
Write-Host ''
if ($result.Failed) {
    Write-Host "  The original registry keys are saved as .reg files in $($script:SB.Root)\backups\<run>\reg (double-click to import)," -ForegroundColor DarkGray
    Write-Host '  or use System Restore: Win+R -> rstrui -> pick the "SafeBoost" restore point.' -ForegroundColor DarkGray
}
Write-Host "  Log: $($script:SB.LogFile)" -ForegroundColor DarkGray
