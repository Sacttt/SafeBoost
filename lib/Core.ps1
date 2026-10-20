# SafeBoost - core engine
# Every change goes through this file. Each function records the ORIGINAL state
# before touching anything, so Restore.ps1 can put the PC back exactly as it was.

$script:SBVersion = '2.0.0'

$script:SB = @{
    Root       = Join-Path $env:ProgramData 'SafeBoost'
    Session    = $null
    SessionDir = $null
    Preset     = $null
    DryRun     = $false
    LogFile    = $null
    Changes    = New-Object System.Collections.ArrayList
    Exported   = @{}
    Stats      = @{ Applied = 0; Skipped = 0; Failed = 0 }
}

# Services SafeBoost will NEVER touch, even if someone edits the tweak list.
$script:SBProtectedServices = @(
    'wuauserv','UsoSvc','WaaSMedicSvc','BITS','TrustedInstaller','CryptSvc','Winmgmt','RpcSs','RpcEptMapper',
    'DcomLaunch','EventLog','Schedule','ProfSvc','Dhcp','Dnscache','NlaSvc','nsi','LanmanWorkstation','mpssvc',
    'BFE','WinDefend','WdNisSvc','SecurityHealthService','wscsvc','Sense','AudioSrv','Audiosrv','AudioEndpointBuilder',
    'PlugPlay','Power','SamSs','LSM','gpsvc','Themes','ShellHWDetection','StateRepository','AppXSvc','ClipSVC',
    'TokenBroker','wlidsvc','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','GamingServices',
    'GamingServicesNet','BrokerInfrastructure','CoreMessagingRegistrar','SystemEventsBroker','TimeBrokerSvc',
    'UserManager','Wcmsvc','WlanSvc','netprofm','EntAppSvc','InstallService','DeviceInstall','vds','VSS'
)

function Write-SBLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERR','SKIP','DRY','STEP')][string]$Level = 'INFO'
    )
    $colors = @{ INFO='Gray'; OK='Green'; WARN='Yellow'; ERR='Red'; SKIP='DarkGray'; DRY='Cyan'; STEP='Magenta' }
    $line = '[{0}] [{1,-4}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($null -ne $global:SBLogQueue) { $global:SBLogQueue.Enqueue($line) }
    else { Write-Host $line -ForegroundColor $colors[$Level] }
    if ($script:SB.LogFile) {
        try { Add-Content -LiteralPath $script:SB.LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}

function Test-SBAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SBWindowsBuild {
    return [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
}

function Start-SBSession {
    param([string]$Preset, [switch]$DryRun)
    $script:SB.DryRun  = [bool]$DryRun
    $script:SB.Preset  = $Preset
    $script:SB.Session = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:SB.Changes.Clear()
    $script:SB.Exported = @{}
    $script:SB.Stats = @{ Applied = 0; Skipped = 0; Failed = 0 }
    $folder = if ($DryRun) { 'dryruns' } else { 'backups' }
    $script:SB.SessionDir = Join-Path $script:SB.Root (Join-Path $folder $script:SB.Session)
    New-Item -ItemType Directory -Path (Join-Path $script:SB.SessionDir 'reg') -Force | Out-Null
    $script:SB.LogFile = Join-Path $script:SB.SessionDir 'log.txt'
    Write-SBLog "SafeBoost $script:SBVersion session $($script:SB.Session) | preset: $Preset | dry run: $DryRun" 'STEP'
    Save-SBSession
}

function Save-SBSession {
    if (-not $script:SB.SessionDir) { return }
    $data = [ordered]@{
        Tool     = 'SafeBoost'
        Version  = $script:SBVersion
        Session  = $script:SB.Session
        Preset   = $script:SB.Preset
        DryRun   = $script:SB.DryRun
        Computer = $env:COMPUTERNAME
        User     = $env:USERNAME
        Build    = (Get-SBWindowsBuild)
        Saved    = (Get-Date).ToString('o')
        Changes  = @($script:SB.Changes)
    }
    # Written after EVERY change, so even a crash/power loss mid-run leaves a usable undo file.
    $json = $data | ConvertTo-Json -Depth 8
    $target = Join-Path $script:SB.SessionDir 'changes.json'
    $tmp = "$target.tmp"
    Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $target -Force
}

function Add-SBChange {
    param([Parameter(Mandatory)][hashtable]$Change)
    $Change.Time = (Get-Date).ToString('o')
    [void]$script:SB.Changes.Add([pscustomobject]$Change)
    $script:SB.Stats.Applied++
    Save-SBSession
}

# ---------------------------------------------------------------- Registry

function ConvertTo-SBRegExePath([string]$Path) {
    return ($Path -replace '^HKCU:\\?', 'HKCU\' -replace '^HKLM:\\?', 'HKLM\' -replace '^HKU:\\?', 'HKU\')
}

function Get-SBRegValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $r = [ordered]@{ Exists = $false; Value = $null; Kind = $null; KeyExists = $false }
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key) { return [pscustomobject]$r }
    $r.KeyExists = $true
    $n = if ($Name -eq '(default)') { '' } else { $Name }
    if ($key.GetValueNames() -contains $n) {
        $r.Exists = $true
        $r.Value  = $key.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
        $r.Kind   = $key.GetValueKind($n).ToString()
    }
    return [pscustomobject]$r
}

function Test-SBSameValue($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
    return ((@($a) | ForEach-Object { "$_" }) -join '|') -eq ((@($b) | ForEach-Object { "$_" }) -join '|')
}

function ConvertTo-SBTypedValue($Value, [string]$Type) {
    switch ($Type) {
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        'Binary'      { return [byte[]]@($Value) }
        'MultiString' { return [string[]]@($Value) }
        default       { return [string]$Value }
    }
}

function Export-SBRegKey([string]$Path) {
    if ($script:SB.DryRun -or $script:SB.Exported.ContainsKey($Path)) { return }
    $script:SB.Exported[$Path] = $true
    $file = Join-Path $script:SB.SessionDir ('reg\{0:D3}.reg' -f $script:SB.Exported.Count)
    & reg.exe export (ConvertTo-SBRegExePath $Path) $file /y 2>&1 | Out-Null
}

function Set-SBRegistry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')][string]$Type = 'DWord',
        [Parameter(Mandatory)]$Value,
        [string]$TweakId
    )
    $before = Get-SBRegValue -Path $Path -Name $Name
    if ($Value -is [scriptblock]) { $Value = & $Value $before.Value }
    $Value = ConvertTo-SBTypedValue $Value $Type
    $label = "$Path\$Name = $Value"

    if ($before.Exists -and $before.Kind -eq $Type -and (Test-SBSameValue $before.Value $Value)) {
        Write-SBLog "Already set  $label" 'SKIP'; $script:SB.Stats.Skipped++; return $true
    }
    if ($script:SB.DryRun) { Write-SBLog "Would set    $label (now: $(if ($before.Exists) { $before.Value } else { '<not set>' }))" 'DRY'; return $true }

    try {
        $createdRoot = $null
        if (-not $before.KeyExists) {
            $p = $Path
            while (-not (Test-Path -LiteralPath (Split-Path $p -Parent))) { $p = Split-Path $p -Parent }
            $createdRoot = $p
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        } else {
            Export-SBRegKey $Path
        }
        if ($Name -eq '(default)') {
            Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop
        } else {
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Add-SBChange @{
            Kind = 'Registry'; TweakId = $TweakId; Path = $Path; Name = $Name; Type = $Type; NewValue = $Value
            Existed = $before.Exists; OldValue = $before.Value; OldType = $before.Kind; CreatedKey = $createdRoot
        }
        Write-SBLog "Set          $label" 'OK'
        return $true
    } catch {
        Write-SBLog "FAILED       $label :: $($_.Exception.Message)" 'ERR'
        $script:SB.Stats.Failed++
        return $false
    }
}

function Remove-SBEmptyKeys([string]$Path, [string]$StopAt) {
    $p = $Path
    while ($p) {
        $k = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        } else { break }
        if ($p -eq $StopAt) { break }
        $p = Split-Path $p -Parent
    }
}

# ---------------------------------------------------------------- Services

function Get-SBServiceStartMode([string]$Name) {
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $start = (Get-ItemProperty -LiteralPath $k -Name Start -ErrorAction SilentlyContinue).Start
    $delayed = (Get-ItemProperty -LiteralPath $k -Name DelayedAutostart -ErrorAction SilentlyContinue).DelayedAutostart
    switch ($start) {
        2 { if ($delayed -eq 1) { return 'delayed-auto' } else { return 'auto' } }
        3 { return 'demand' }
        4 { return 'disabled' }
        default { return $null }   # boot/system drivers or missing: never touched
    }
}

function Set-SBService {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('demand','disabled')][string]$StartMode,
        [switch]$StopNow,
        [string]$TweakId
    )
    if ($script:SBProtectedServices -contains $Name) { Write-SBLog "Protected service $Name - refusing to change it" 'WARN'; return $false }
    if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { Write-SBLog "Service $Name not present on this PC" 'SKIP'; $script:SB.Stats.Skipped++; return $true }
    $old = Get-SBServiceStartMode $Name
    if (-not $old) { Write-SBLog "Service $Name has an unusual start type - leaving it alone" 'SKIP'; return $true }
    if ($old -eq $StartMode) { Write-SBLog "Service $Name already $StartMode" 'SKIP'; $script:SB.Stats.Skipped++; return $true }
    if ($script:SB.DryRun) { Write-SBLog "Would set service $Name : $old -> $StartMode" 'DRY'; return $true }

    $out = & sc.exe config $Name start= $StartMode 2>&1
    if ($LASTEXITCODE -ne 0) { Write-SBLog "FAILED service $Name :: $out" 'ERR'; $script:SB.Stats.Failed++; return $false }
    Add-SBChange @{ Kind = 'Service'; TweakId = $TweakId; Name = $Name; OldMode = $old; NewMode = $StartMode }
    Write-SBLog "Service $Name : $old -> $StartMode" 'OK'
    if ($StopNow) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    return $true
}

# ---------------------------------------------------------------- Scheduled tasks

function Disable-SBTask {
    param([Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName, [string]$TweakId)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { Write-SBLog "Task $TaskPath$TaskName not present" 'SKIP'; $script:SB.Stats.Skipped++; return $true }
    if ($t.State -eq 'Disabled') { Write-SBLog "Task $TaskName already disabled" 'SKIP'; $script:SB.Stats.Skipped++; return $true }
    if ($script:SB.DryRun) { Write-SBLog "Would disable task $TaskPath$TaskName" 'DRY'; return $true }
    try {
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        Add-SBChange @{ Kind = 'Task'; TweakId = $TweakId; TaskPath = $TaskPath; TaskName = $TaskName }
        Write-SBLog "Disabled task $TaskPath$TaskName" 'OK'
        return $true
    } catch { Write-SBLog "FAILED task $TaskName :: $($_.Exception.Message)" 'ERR'; $script:SB.Stats.Failed++; return $false }
}

# ---------------------------------------------------------------- Power plan

function Get-SBActivePowerScheme {
    $o = & powercfg.exe /getactivescheme 2>$null
    if ("$o" -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}

function Test-SBLaptop {
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { return $true }
    $types = (Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes
    return [bool]($types | Where-Object { $_ -in 8,9,10,11,12,14,18,21,30,31,32 })
}

function Set-SBPowerPlan {
    param([string]$TweakId)
    $planName = 'SafeBoost Performance'
    $old = Get-SBActivePowerScheme
    $laptop = Test-SBLaptop
    # Ultimate Performance on desktops, High Performance on laptops (less heat/battery drain)
    $template = if ($laptop) { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' } else { 'e9a42b02-d5df-448d-aa00-03f14749eb61' }

    $existing = $null
    foreach ($line in (& powercfg.exe /list)) {
        if ($line -match '([0-9a-fA-F-]{36})\s+\((.+?)\)' -and $Matches[2] -eq $planName) { $existing = $Matches[1] }
    }
    if ($existing -and $old -eq $existing) { Write-SBLog "Power plan '$planName' already active" 'SKIP'; $script:SB.Stats.Skipped++; return $true }
    if ($script:SB.DryRun) { Write-SBLog "Would create/activate power plan '$planName' (laptop: $laptop)" 'DRY'; return $true }

    $created = $false
    $guid = $existing
    if (-not $guid) {
        $out = & powercfg.exe -duplicatescheme $template 2>&1
        if ("$out" -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $guid = $Matches[1]; $created = $true
            & powercfg.exe -changename $guid $planName 'Created by SafeBoost - delete any time' | Out-Null
        } else {
            Write-SBLog "This PC does not allow extra power plans (common on Modern Standby laptops). Skipping - nothing changed." 'WARN'
            return $true
        }
    }
    # Plugged-in only: no USB selective suspend, no PCIe link power saving. Battery settings untouched.
    & powercfg.exe /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
    & powercfg.exe /setacvalueindex $guid 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null | Out-Null
    & powercfg.exe /setactive $guid | Out-Null
    if ((Get-SBActivePowerScheme) -ne $guid) {
        Write-SBLog 'Could not activate the new power plan - leaving your old one active.' 'WARN'
        if ($created) { & powercfg.exe -delete $guid | Out-Null }
        return $false
    }
    Add-SBChange @{ Kind = 'PowerPlan'; TweakId = $TweakId; OldScheme = $old; NewScheme = $guid; Created = $created }
    Write-SBLog "Power plan '$planName' active$(if ($laptop) { ' (laptop: High Performance base - plug in while gaming)' })" 'OK'
    return $true
}

# ---------------------------------------------------------------- Apps

function Test-SBProtectedApp([string]$Name, $Protected) {
    foreach ($p in $Protected) { if ($Name -like $p) { return $true } }
    return $false
}

function Remove-SBApp {
    param([Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)]$Protected, [switch]$AllUsers, [string]$TweakId)
    if (Test-SBProtectedApp $Pattern $Protected) { Write-SBLog "App pattern '$Pattern' is on the protected list - refusing" 'WARN'; return }
    $pkgs = if ($AllUsers) { Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction SilentlyContinue } else { Get-AppxPackage -Name $Pattern -ErrorAction SilentlyContinue }
    $pkgs = @($pkgs | Where-Object { $_ -and -not $_.NonRemovable -and -not $_.IsFramework })
    if ($pkgs.Count -eq 0) { Write-SBLog "App $Pattern not installed" 'SKIP'; $script:SB.Stats.Skipped++ }
    foreach ($pkg in $pkgs) {
        if (Test-SBProtectedApp $pkg.Name $Protected) { Write-SBLog "Protected app $($pkg.Name) - skipping" 'WARN'; continue }
        if ($script:SB.DryRun) { Write-SBLog "Would remove app $($pkg.Name)" 'DRY'; continue }
        try {
            if ($AllUsers) { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
            else { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop }
            Add-SBChange @{ Kind = 'App'; TweakId = $TweakId; Name = $pkg.Name; FullName = $pkg.PackageFullName; AllUsers = [bool]$AllUsers }
            Write-SBLog "Removed app $($pkg.Name)" 'OK'
        } catch { Write-SBLog "Could not remove $($pkg.Name) :: $($_.Exception.Message)" 'WARN'; $script:SB.Stats.Failed++ }
    }
    if ($AllUsers -and -not $script:SB.DryRun) {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern -and -not (Test-SBProtectedApp $_.DisplayName $Protected) } | ForEach-Object {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
                Add-SBChange @{ Kind = 'App'; TweakId = $TweakId; Name = $_.DisplayName; FullName = $_.PackageName; Provisioned = $true }
                Write-SBLog "Stopped $($_.DisplayName) from installing for new users" 'OK'
            } catch { Write-SBLog "Could not deprovision $($_.DisplayName)" 'WARN' }
        }
    }
}

# ---------------------------------------------------------------- Restore point

function New-SBRestorePoint {
    if ($script:SB.DryRun) { Write-SBLog 'Would create a System Restore point' 'DRY'; return $true }
    Write-SBLog 'Creating System Restore point (can take a minute)...' 'STEP'
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freq = Get-SBRegValue -Path $key -Name 'SystemRestorePointCreationFrequency'
    try {
        try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop } catch { }
        # Windows normally allows only one restore point per 24h; lift that just for this call.
        New-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
        Checkpoint-Computer -Description "SafeBoost $($script:SB.Session)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq "SafeBoost $($script:SB.Session)" }
        if ($rp) { Write-SBLog "Restore point created: 'SafeBoost $($script:SB.Session)'" 'OK'; return $true }
        Write-SBLog 'Restore point command ran but the point could not be verified.' 'WARN'; return $false
    } catch {
        Write-SBLog "Restore point failed: $($_.Exception.Message)" 'WARN'; return $false
    } finally {
        if ($freq.Exists) { New-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value $freq.Value -Force | Out-Null }
        else { Remove-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- Undo

function Undo-SBChange {
    param([Parameter(Mandatory)]$Change)
    try {
        switch ($Change.Kind) {
            'Registry' {
                if ($Change.Existed) {
                    $v = ConvertTo-SBTypedValue $Change.OldValue $Change.OldType
                    if ($Change.Name -eq '(default)') { Set-Item -LiteralPath $Change.Path -Value $v -ErrorAction Stop }
                    else { New-ItemProperty -LiteralPath $Change.Path -Name $Change.Name -PropertyType $Change.OldType -Value $v -Force -ErrorAction Stop | Out-Null }
                    Write-SBLog "Restored $($Change.Path)\$($Change.Name) = $v" 'OK'
                } else {
                    if ($Change.Name -eq '(default)') {
                        if (Test-Path -LiteralPath $Change.Path) { & reg.exe delete (ConvertTo-SBRegExePath $Change.Path) /ve /f 2>&1 | Out-Null }
                    } else {
                        Remove-ItemProperty -LiteralPath $Change.Path -Name $Change.Name -ErrorAction SilentlyContinue
                    }
                    if ($Change.CreatedKey) { Remove-SBEmptyKeys $Change.Path $Change.CreatedKey }
                    Write-SBLog "Removed $($Change.Path)\$($Change.Name) (was not set before)" 'OK'
                }
            }
            'Service' {
                $out = & sc.exe config $Change.Name start= $Change.OldMode 2>&1
                if ($LASTEXITCODE -ne 0) { throw "$out" }
                if ($Change.OldMode -in 'auto','delayed-auto') { Start-Service -Name $Change.Name -ErrorAction SilentlyContinue }
                Write-SBLog "Service $($Change.Name) back to $($Change.OldMode)" 'OK'
            }
            'Task' {
                Enable-ScheduledTask -TaskPath $Change.TaskPath -TaskName $Change.TaskName -ErrorAction Stop | Out-Null
                Write-SBLog "Re-enabled task $($Change.TaskName)" 'OK'
            }
            'PowerPlan' {
                if ($Change.OldScheme) { & powercfg.exe /setactive $Change.OldScheme | Out-Null }
                if ($Change.Created) { & powercfg.exe -delete $Change.NewScheme 2>&1 | Out-Null }
                Write-SBLog 'Previous power plan restored' 'OK'
            }
            'App' {
                Write-SBLog "App $($Change.Name) was removed - reinstall it free from the Microsoft Store if you want it back" 'WARN'
            }
            default { Write-SBLog "Info-only entry: $($Change.Kind)" 'SKIP' }
        }
        return $true
    } catch {
        Write-SBLog "Could not undo $($Change.Kind) $($Change.Name) :: $($_.Exception.Message)" 'ERR'
        return $false
    }
}

# ---------------------------------------------------------------- Runs (used by Restore.ps1 and the GUI)

function Get-SBRuns {
    param([switch]$IncludeUndone)
    $backupRoot = Join-Path $script:SB.Root 'backups'
    $runs = foreach ($d in (Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $file = Join-Path $d.FullName 'changes.json'
        if (-not (Test-Path -LiteralPath $file)) { continue }
        try { $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { continue }
        $count = @($data.Changes | Where-Object { $_ }).Count
        if ($count -eq 0) { continue }
        $undone = Test-Path -LiteralPath (Join-Path $d.FullName 'UNDONE')
        if ($undone -and -not $IncludeUndone) { continue }
        $date = $null
        try { $date = [datetime]::ParseExact($d.Name, 'yyyyMMdd-HHmmss', $null) } catch { }
        [pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Preset = $data.Preset; Count = $count; Undone = $undone; Date = $date
                           Apps = @($data.Changes | Where-Object { $_.Kind -eq 'App' }).Count }
    }
    return @($runs)
}

function Invoke-SBUndoRun {
    # Undo the given run AND every newer run that is still active, newest first,
    # so values are never restored out of order.
    param([Parameter(Mandatory)][string]$Session)
    $active = @(Get-SBRuns)
    $idx = -1
    for ($i = 0; $i -lt $active.Count; $i++) { if ($active[$i].Name -eq $Session) { $idx = $i } }
    if ($idx -lt 0) { Write-SBLog "Run $Session not found or already undone" 'WARN'; return [pscustomobject]@{ Failed = 0; Runs = 0 } }
    $failed = 0
    foreach ($r in $active[0..$idx]) {
        $data = Get-Content -LiteralPath (Join-Path $r.Dir 'changes.json') -Raw | ConvertFrom-Json
        $changes = @($data.Changes | Where-Object { $_ })
        Write-SBLog "Undoing run $($r.Name) ($($changes.Count) changes)" 'STEP'
        for ($i = $changes.Count - 1; $i -ge 0; $i--) { if (-not (Undo-SBChange -Change $changes[$i])) { $failed++ } }
        Set-Content -LiteralPath (Join-Path $r.Dir 'UNDONE') -Value (Get-Date).ToString('o')
    }
    if ($failed) { Write-SBLog "$failed item(s) could not be restored automatically - see the .reg files in the backup folder or use System Restore" 'WARN' }
    else { Write-SBLog 'Undo complete. Restart your PC to finish.' 'OK' }
    return [pscustomobject]@{ Failed = $failed; Runs = $idx + 1 }
}
