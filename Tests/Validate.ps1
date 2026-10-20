# Static safety checks for the tweak catalog and app lists. Runs on any OS (no changes made).
# Exit code 0 = all good.
$ErrorActionPreference = 'Stop'
if (-not $env:ProgramData) { $env:ProgramData = [IO.Path]::GetTempPath() }
$root = Split-Path $PSScriptRoot -Parent
$fail = 0
function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }

# 1. Every script parses and is pure ASCII (Windows PowerShell 5.1 misreads UTF-8 without BOM)
foreach ($f in Get-ChildItem -Path $root -Recurse -Include *.ps1, *.json, *.bat, *.xaml) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    if ($bytes | Where-Object { $_ -gt 127 }) { Fail "$($f.Name) contains non-ASCII characters" }
    if ($f.Extension -eq '.ps1') {
        $tokens = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        foreach ($e in $errs) { Fail "$($f.Name):$($e.Extent.StartLineNumber) $($e.Message)" }
    }
}

# 2. Load catalog (stub the one Windows-only call it makes at definition time)
function Get-SBWindowsBuild { 26100 }
. "$root\lib\Core.ps1"
function Get-SBWindowsBuild { 26100 }
. "$root\lib\Tweaks.ps1"

$ids = @{}
$validTypes = 'DWord','QWord','String','ExpandString','MultiString','Binary'
# Registry areas that must never be written by this tool
$forbidden = @(
    'Policies\\Microsoft\\Windows Defender', 'WindowsUpdate', 'SmartScreen', 'EnableLUA', 'ConsentPromptBehavior',
    'FeatureSettingsOverride', 'DeviceGuard', 'Control\\Lsa', 'Winlogon', 'BootExecute', 'SafeBoot', 'Firewall'
)
foreach ($t in $script:SBTweaks) {
    if (-not $t.Id -or -not $t.Name -or -not $t.Why -or -not $t.Category) { Fail "Tweak missing Id/Name/Why/Category: $($t.Id)" }
    if ($ids.ContainsKey($t.Id)) { Fail "Duplicate tweak id $($t.Id)" }; $ids[$t.Id] = 1
    foreach ($p in @($t.Presets)) { if ($p -and $p -notin 'Safe','Gaming','Max') { Fail "$($t.Id): unknown preset $p" } }
    if ($t.Category -notin 'Privacy','Background','Responsiveness','Cleanup','Gaming','Max','Space','Extras') { Fail "$($t.Id): unknown category $($t.Category)" }
    foreach ($r in @($t.Registry)) {
        if (-not $r) { continue }
        if ($r.Path -notmatch '^(HKCU|HKLM):\\') { Fail "$($t.Id): bad hive in $($r.Path)" }
        if ($r.Type -notin $validTypes) { Fail "$($t.Id): bad type $($r.Type)" }
        if (-not $r.Name) { Fail "$($t.Id): missing value name" }
        if ($null -eq $r.Value) { Fail "$($t.Id): null value for $($r.Name)" }
        # The ONLY Windows Update value allowed: wait for the user to restart (updates still install).
        $allowed = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoRebootWithLoggedOnUsers')
        if ($allowed -notcontains "$($r.Path)\$($r.Name)") {
            foreach ($bad in $forbidden) { if ("$($r.Path)\$($r.Name)" -match $bad) { Fail "$($t.Id): touches forbidden area '$bad'" } }
        }
    }
    foreach ($s in @($t.Services)) {
        if (-not $s) { continue }
        if ($script:SBProtectedServices -contains $s.Name) { Fail "$($t.Id): protected service $($s.Name)" }
        if ($s.Mode -notin 'demand','disabled') { Fail "$($t.Id): bad service mode $($s.Mode)" }
    }
    if ($t.Action -and $t.Action -notin 'PowerPlan','Cleanup','Hibernate','ReservedStorage','CompactOS') { Fail "$($t.Id): unknown action $($t.Action)" }
}

# Safe preset must never contain anything needing a reboot or touching services beyond telemetry
foreach ($t in ($script:SBTweaks | Where-Object { $_.Presets -contains 'Safe' })) {
    if ($t.Reboot) { Fail "Safe preset tweak $($t.Id) needs a reboot - move it to Gaming" }
}

# Scriptblock values must produce the expected merge
$wo = ($script:SBTweaks | Where-Object Id -eq 'windowedopt').Registry[0].Value
if ((& $wo $null) -ne 'SwapEffectUpgradeEnable=1;') { Fail 'windowedopt merge from empty' }
if ((& $wo 'VRROptimizeEnable=0;') -ne 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;') { Fail 'windowedopt keeps other settings' }
if ((& $wo 'SwapEffectUpgradeEnable=0;VRROptimizeEnable=1;') -ne 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;') { Fail 'windowedopt flips existing flag' }

# 3. App lists: nothing removable may match a protected pattern; critical apps must be protected
$apps = Get-Content "$root\config\apps.json" -Raw | ConvertFrom-Json
foreach ($a in @($apps.Bloat) + @($apps.Extra)) {
    if (Test-SBProtectedApp $a $apps.Protected) { Fail "App '$a' is in a removal list but matches a protected pattern" }
    if ($a -match '^\*[^*]{0,3}\*$') { Fail "App pattern '$a' is dangerously broad" }
}
$mustProtect = 'Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.VCLibs.140.00','Microsoft.UI.Xaml.2.8',
               'Microsoft.XboxIdentityProvider','Microsoft.GamingApp','Microsoft.GamingServices','Microsoft.SecHealthUI',
               'Microsoft.Windows.ShellExperienceHost','MicrosoftWindows.Client.CBS','Microsoft.MicrosoftEdge.Stable',
               'Microsoft.WindowsAppRuntime.1.5','NVIDIACorp.NVIDIAControlPanel','RealtekSemiconductorCorp.RealtekAudioControl',
               'AdvancedMicroDevicesInc-2.AMDRadeonSoftware','AppUp.IntelGraphicsExperience','Microsoft.WindowsCalculator'
foreach ($m in $mustProtect) { if (-not (Test-SBProtectedApp $m $apps.Protected)) { Fail "Critical app $m is not protected" } }
# Real-world bloat names should not be accidentally protected
foreach ($b in 'king.com.CandyCrushSaga','Microsoft.BingNews','Clipchamp.Clipchamp','Microsoft.Getstarted','Microsoft.MicrosoftSolitaireCollection') {
    if (Test-SBProtectedApp $b $apps.Protected) { Fail "Bloat app $b is wrongly protected" }
}

if ($fail) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "All checks passed ($($script:SBTweaks.Count) tweaks, $(@($apps.Bloat).Count + @($apps.Extra).Count) app patterns)" -ForegroundColor Green
exit 0
