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

$backupRoot = Join-Path $script:SB.Root 'backups'
$runs = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
          Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'changes.json') } |
          Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName 'UNDONE')) } |
          Sort-Object Name -Descending)

if ($runs.Count -eq 0) {
    Write-Host 'No SafeBoost runs to undo.' -ForegroundColor Yellow
    Write-Host 'You can still use Windows System Restore: press Win+R, type rstrui, pick a "SafeBoost" restore point.' -ForegroundColor DarkGray
    exit 0
}

$selected = @()
if ($All)         { $selected = $runs }
elseif ($Latest)  { $selected = @($runs[0]) }
elseif ($Session) { $selected = @($runs | Where-Object Name -eq $Session); if (-not $selected) { Write-Host "Run $Session not found (or already undone)." -ForegroundColor Red; exit 1 } }
else {
    Write-Host ''
    Write-Host '  SafeBoost runs you can undo (newest first):' -ForegroundColor Cyan
    $i = 0
    foreach ($r in $runs) {
        $i++
        $d = Get-Content -LiteralPath (Join-Path $r.FullName 'changes.json') -Raw | ConvertFrom-Json
        Write-Host ('  {0,2}. {1}  preset: {2,-7} changes: {3}' -f $i, $r.Name, $d.Preset, @($d.Changes).Count)
    }
    Write-Host '   A. Undo ALL of them'
    Write-Host ''
    $in = Read-Host '  Which one? (number / A / Enter to cancel)'
    if (-not $in) { exit 0 }
    if ($in -match '^[aA]$') { $selected = $runs }
    elseif ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $runs.Count) {
        # Undoing an older run while newer runs exist could restore stale values; undo newer ones too.
        $idx = [int]$in - 1
        $selected = @($runs[0..$idx])
        if ($idx -gt 0) { Write-Host "  Note: the $idx newer run(s) will be undone first so nothing is left half-restored." -ForegroundColor Yellow }
    } else { exit 0 }
}

if (-not $Silent) {
    if ((Read-Host "  Undo $($selected.Count) run(s)? (y/N)") -notmatch '^[yY]') { exit 0 }
}

$script:SB.LogFile = Join-Path $script:SB.Root ('undo-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$failed = 0
foreach ($r in $selected) {
    $data = Get-Content -LiteralPath (Join-Path $r.FullName 'changes.json') -Raw | ConvertFrom-Json
    $changes = @($data.Changes)
    Write-SBLog "Undoing run $($r.Name) ($($changes.Count) changes)" 'STEP'
    for ($i = $changes.Count - 1; $i -ge 0; $i--) {
        if (-not (Undo-SBChange -Change $changes[$i])) { $failed++ }
    }
    Set-Content -LiteralPath (Join-Path $r.FullName 'UNDONE') -Value (Get-Date).ToString('o')
}

Write-Host ''
if ($failed) {
    Write-Host "  Undo finished with $failed item(s) that could not be restored automatically." -ForegroundColor Yellow
    Write-Host "  The original registry keys are also saved as .reg files in $backupRoot\<run>\reg (double-click to import)," -ForegroundColor DarkGray
    Write-Host '  or use System Restore: Win+R -> rstrui -> pick the "SafeBoost" restore point.' -ForegroundColor DarkGray
} else {
    Write-Host '  Undo complete. Restart your PC to finish.' -ForegroundColor Green
}
Write-Host "  Log: $($script:SB.LogFile)" -ForegroundColor DarkGray
