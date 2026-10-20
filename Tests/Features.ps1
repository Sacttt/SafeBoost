# Startup manager, disk cleanup and installed-programs checks on a throwaway Windows machine.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\lib\Core.ps1"; . "$root\lib\Startup.ps1"; . "$root\lib\Cleanup.ps1"; . "$root\lib\Programs.ps1"
$fail = 0
function Fail($m) { Write-Host "::error::$m"; $script:fail++ }
trap {
    Write-Host "::error::Unexpected error: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage -replace '\s+', ' ')"
    exit 1
}

# ---- Startup: create a fake startup entry, disable it, undo, verify exact restore
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
New-ItemProperty -Path $runKey -Name 'SafeBoostTestApp' -Value "`"$env:SystemRoot\notepad.exe`" /background" -PropertyType String -Force | Out-Null
$before = Get-SBRegValue -Path $approved -Name 'SafeBoostTestApp'
$item = Get-SBStartupItems | Where-Object Name -eq 'SafeBoostTestApp'
if (-not $item) { Fail 'Startup item not detected' }
elseif (-not $item.Enabled) { Fail 'New startup item should be enabled' }
else {
    if ($item.Description -notmatch 'Notepad') { Fail "Expected description from notepad.exe, got '$($item.Description)'" }
    Start-SBSession -Preset 'Startup test'
    [void](Set-SBStartupItem -Item $item -Enable $false)
    Save-SBSession
    $after = Get-SBStartupItems | Where-Object Name -eq 'SafeBoostTestApp'
    if ($after.Enabled) { Fail 'Startup item still enabled after disabling' }
    $undo = Invoke-SBUndoRun -Session $script:SB.Session
    $restored = Get-SBRegValue -Path $approved -Name 'SafeBoostTestApp'
    if ($restored.Exists -ne $before.Exists) { Fail 'StartupApproved value not restored to its original state' }
    if (-not (Get-SBStartupItems | Where-Object Name -eq 'SafeBoostTestApp').Enabled) { Fail 'Startup item not enabled again after undo' }
}
Remove-ItemProperty -Path $runKey -Name 'SafeBoostTestApp' -ErrorAction SilentlyContinue
Write-Host "Startup items found on this machine: $(@(Get-SBStartupItems).Count)"

# ---- Cleanup: scan works, cleaning planted temp files frees them, a recent temp file survives
$scan = Get-SBCleanupScan
if (@($scan.Targets).Count -lt 8) { Fail 'Cleanup scan returned too few targets' }
$old = Join-Path $env:TEMP 'safeboost-old.tmp'; $new = Join-Path $env:TEMP 'safeboost-new.tmp'
Set-Content -Path $old -Value ('x' * 100000); (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-5)
Set-Content -Path $new -Value 'keep me'
$res = Invoke-SBDiskCleanup -Ids 'temp', 'dumps', 'logs', 'wer', 'docache', 'wucache'
if (Test-Path $old) { Fail 'Old temp file was not cleaned' }
if (-not (Test-Path $new)) { Fail 'A brand-new temp file was deleted (should only remove files older than 1 day)' }
Remove-Item $new -ErrorAction SilentlyContinue
foreach ($s in 'wuauserv', 'bits') { $svc = Get-Service $s -ErrorAction SilentlyContinue; if ($svc -and $svc.StartType -eq 'Disabled') { Fail "$s left disabled" } }
Write-Host "Cleanup freed $(Format-SBSize $res.Freed)"

# ---- Programs: list is readable, runtimes are protected
$progs = @(Get-SBInstalledPrograms)
if ($progs.Count -lt 3) { Fail "Only $($progs.Count) programs found" }
$vc = $progs | Where-Object { $_.Name -match 'Visual C\+\+' } | Select-Object -First 1
if ($vc -and -not $vc.Keep) { Fail 'Visual C++ runtime should be marked Keep' }
try { if ($vc) { Start-SBUninstall -Program $vc; Fail 'Uninstalling a protected runtime was not blocked' } } catch { }
Write-Host "Programs found: $($progs.Count) (biggest: $($progs | Sort-Object Bytes -Descending | Select-Object -First 1 -ExpandProperty Name))"

if ($fail) { throw "$fail feature check(s) failed" }
Write-Host '::notice::Feature tests OK: startup toggle + undo, cleanup, programs list'
