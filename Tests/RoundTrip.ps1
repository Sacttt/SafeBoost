# Apply -> Undo -> compare. Proves every change SafeBoost makes is fully reversible.
# Runs on a throwaway Windows machine (GitHub Actions windows-latest). Needs admin.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\lib\Core.ps1"
. "$root\lib\Tweaks.ps1"

function Get-State {
    $s = [ordered]@{}
    foreach ($t in Get-SBTweaks) {
        foreach ($r in @($t.Registry)) {
            if (-not $r) { continue }
            $v = Get-SBRegValue -Path $r.Path -Name $r.Name
            $s["REG $($r.Path)\$($r.Name)"] = if ($v.Exists) { "$($v.Kind):$((@($v.Value) | ForEach-Object { "$_" }) -join ',')" } else { "<absent> key=$($v.KeyExists)" }
        }
        foreach ($sv in @($t.Services)) { if ($sv) { $s["SVC $($sv.Name)"] = "$(Get-SBServiceStartMode $sv.Name)" } }
        foreach ($tk in @($t.Tasks)) {
            if ($tk) { $x = Get-ScheduledTask -TaskPath $tk.Path -TaskName $tk.Name -ErrorAction SilentlyContinue; $s["TASK $($tk.Name)"] = if ($x) { ($x.State -eq 'Disabled').ToString() } else { 'absent' } }
        }
    }
    $s['POWER'] = Get-SBActivePowerScheme
    $s['PLANS'] = ((& powercfg.exe /list) -join '|') -replace '\s+\*', ''
    return $s
}

$before = Get-State
& "$root\SafeBoost.ps1" -Preset Max -Silent -SkipRestorePoint -NoAppRemoval
# Every tweak that is not in a preset (skip the two slow disk actions: CompactOS takes 20+ min, reserved storage depends on update state)
$customIds = @(Get-SBTweaks | Where-Object { $_.Supported -and -not @($_.Presets).Count -and $_.Id -notin 'compactos', 'reservedstorage' } | ForEach-Object { $_.Id })
Write-Host "Custom-only tweaks tested: $($customIds -join ', ')"
& "$root\SafeBoost.ps1" -Preset Custom -Only $customIds -Silent -SkipRestorePoint
$during = Get-State

$changed = @($before.Keys | Where-Object { $before[$_] -ne $during[$_] })
Write-Host "Values changed by SafeBoost: $($changed.Count)"
if ($changed.Count -lt 10) { Write-Host "::error::Only $($changed.Count) values changed"; throw "Expected SafeBoost to change many values, only $($changed.Count) changed" }

& "$root\Restore.ps1" -All -Silent
$after = Get-State

$diff = @($before.Keys | Where-Object { $before[$_] -ne $after[$_] })
foreach ($k in $diff) { Write-Host "::error::NOT RESTORED: $k | before: $($before[$k]) | after: $($after[$k])" }
if ($diff.Count) { throw "$($diff.Count) value(s) were not restored exactly" }
Write-Host "::notice::Round trip OK: $($changed.Count) changes applied and all restored exactly." -ForegroundColor Green
