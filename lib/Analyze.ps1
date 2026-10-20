# SafeBoost - PC analyzer (read-only, changes nothing)
# Finds the things that ACTUALLY cost FPS: wrong refresh rate, RAM without XMP/EXPO,
# single-channel RAM, old GPU drivers, full drives, power-saving plans, background recording.

function Get-SBSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        Time            = (Get-Date).ToString('o')
        Processes       = @(Get-Process).Count
        RamUsedGB       = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        RamTotalGB      = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        RunningServices = @(Get-Service | Where-Object Status -eq 'Running').Count
        StartupItems    = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count
    }
}

function Get-SBFindings {
    $f = New-Object System.Collections.ArrayList
    function Add-F($Sev, $Area, $Text, $Fix) { [void]$f.Add([pscustomobject]@{ Severity = $Sev; Area = $Area; Finding = $Text; Fix = $Fix }) }

    $build = Get-SBWindowsBuild
    $os = Get-CimInstance Win32_OperatingSystem
    $win = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    Add-F 'INFO' 'System' "$win build $build ($($os.Caption))" ''
    if ($build -lt 19045 -and $build -lt 22000) { Add-F 'WARN' 'System' 'Windows 10 is out of date / out of support' 'Update to Windows 10 22H2 at least (or Windows 11) for current GPU drivers and security fixes.' }

    # CPU
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Add-F 'INFO' 'CPU' "$($cpu.Name.Trim()) - $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads" ''

    # RAM
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $totalGB = [math]::Round(($mods | Measure-Object Capacity -Sum).Sum / 1GB)
    if ($mods.Count -gt 0) {
        $cfg = ($mods | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
        $rated = ($mods | Measure-Object Speed -Maximum).Maximum
        Add-F 'INFO' 'RAM' "$totalGB GB in $($mods.Count) stick(s), running at $cfg MT/s" ''
        if ($mods.Count -eq 1 -and -not (Test-SBLaptop)) { Add-F 'BIG' 'RAM' 'Only ONE RAM stick = single-channel memory' 'A second matching stick (dual-channel) commonly gives +10-30% FPS in CPU-heavy games. This is the biggest upgrade-per-dollar on many PCs.' }
        if ($cfg -and $rated -and $cfg -lt $rated) { Add-F 'BIG' 'RAM' "RAM runs at $cfg MT/s but reports $rated MT/s capability" 'Enable XMP (Intel) or EXPO/DOCP (AMD) in your BIOS. Free performance, often +5-15% FPS.' }
        elseif ($cfg -and (($cfg -le 2666 -and $cfg -ge 2000) -or ($cfg -eq 4800))) { Add-F 'TIP' 'RAM' "RAM at $cfg MT/s is a typical default (JEDEC) speed" 'If your RAM box says a higher number (e.g. 3200/3600 or 6000), turn on XMP/EXPO in BIOS.' }
        if ($totalGB -lt 16) { Add-F 'TIP' 'RAM' "$totalGB GB RAM is tight for modern games" '16 GB is the comfortable minimum in 2026; close browsers/Discord while gaming.' }
    }

    # GPU + display
    foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        if ($g.Name -match 'Microsoft Basic|Remote|Virtual|Parsec|Meta') {
            if ($g.Name -match 'Microsoft Basic') { Add-F 'BIG' 'GPU' 'Windows is using the "Microsoft Basic Display Adapter"' 'Your real GPU driver is NOT installed. Install it from nvidia.com / amd.com / intel.com - this alone can be a 10x FPS difference.' }
            continue
        }
        $age = $null
        if ($g.DriverDate) { $age = [int]((Get-Date) - [datetime]$g.DriverDate).TotalDays }
        Add-F 'INFO' 'GPU' "$($g.Name) - driver $($g.DriverVersion)$(if ($null -ne $age) { " ($age days old)" })" ''
        if ($age -gt 180 -and $g.Name -match 'NVIDIA|AMD|Radeon|Arc') { Add-F 'WARN' 'GPU' "GPU driver is $age days old" 'Update from the GPU maker (NVIDIA App / AMD Adrenalin / Intel Arc Control). New games get big fixes in new drivers.' }
        if ($g.CurrentRefreshRate -and $g.MaxRefreshRate -and ($g.MaxRefreshRate - $g.CurrentRefreshRate) -ge 10 -and $g.MaxRefreshRate -le 600) {
            Add-F 'BIG' 'Display' "Monitor running at $($g.CurrentRefreshRate) Hz, but up to $($g.MaxRefreshRate) Hz may be available" 'Settings > System > Display > Advanced display > Choose a refresh rate. Use DisplayPort or HDMI 2.0+. You literally cannot SEE more than your refresh rate.'
        } elseif ($g.CurrentRefreshRate) { Add-F 'INFO' 'Display' "Refresh rate: $($g.CurrentRefreshRate) Hz" '' }
    }

    # HAGS / Game Mode / DVR
    $hags = Get-SBRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    Add-F 'INFO' 'Gaming' "Hardware GPU scheduling: $(if ($hags.Value -eq 2) { 'ON' } elseif ($hags.Exists) { 'OFF' } else { 'default' })" ''
    $gm = Get-SBRegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    if ($gm.Exists -and $gm.Value -eq 0) { Add-F 'WARN' 'Gaming' 'Game Mode is OFF' 'The Gaming preset turns it back on.' }
    $dvr = Get-SBRegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    if (-not $dvr.Exists -or $dvr.Value -ne 0) { Add-F 'TIP' 'Gaming' 'Background game recording (Game DVR) may be on' 'Any SafeBoost preset turns it off.' }

    # Memory integrity (VBS/HVCI) - report only
    $hvci = Get-SBRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    if ($hvci.Value -eq 1) { Add-F 'INFO' 'Security' 'Memory Integrity (Core Isolation) is ON' 'It can cost a few % FPS on older CPUs. Microsoft documents turning it off for gaming, but it is a real security feature - SafeBoost will NOT change it for you. Your call: Windows Security > Device security > Core isolation.' }

    # Power
    $scheme = (& powercfg.exe /getactivescheme) -join ' '
    if ($scheme -match '\((.+)\)') { Add-F 'INFO' 'Power' "Active power plan: $($Matches[1])" '' }
    if ($scheme -match 'Power saver|Energiesparmodus|Ahorro') { Add-F 'BIG' 'Power' 'Power SAVER plan is active' 'Use the Gaming preset (or pick Balanced/High performance).' }
    $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($batt -and $batt.BatteryStatus -eq 1) { Add-F 'BIG' 'Power' 'Laptop is running on BATTERY' 'Plug in to game: laptops cut CPU/GPU power hard on battery.' }

    # Storage
    $sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    if ($sys) {
        $pct = [math]::Round($sys.FreeSpace / $sys.Size * 100)
        Add-F 'INFO' 'Storage' "$env:SystemDrive free: $([math]::Round($sys.FreeSpace/1GB)) GB ($pct%)" ''
        if ($pct -lt 10) { Add-F 'WARN' 'Storage' 'System drive is almost full' 'Keep 15%+ free: Windows needs room for the page file, updates and shader caches.' }
    }
    try {
        $part = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$($part.DiskNumber)" } | Select-Object -First 1
        if ($pd -and $pd.MediaType -eq 'HDD') { Add-F 'BIG' 'Storage' 'Windows is installed on a hard drive (HDD)' 'An SSD is the single biggest "feel" upgrade: boot, loading and stutter all improve massively.' }
        elseif ($pd) { Add-F 'INFO' 'Storage' "System disk: $($pd.FriendlyName) ($($pd.MediaType), $($pd.BusType))" '' }
    } catch { }

    # Background load
    $snap = Get-SBSnapshot
    Add-F 'INFO' 'Load' "$($snap.Processes) processes, $($snap.RunningServices) services, $($snap.RamUsedGB)/$($snap.RamTotalGB) GB RAM in use" ''
    if ($snap.StartupItems -gt 8) { Add-F 'TIP' 'Load' "$($snap.StartupItems) apps start with Windows" 'Task Manager > Startup apps: disable launchers you do not need at boot (SafeBoost does not do this automatically - it is your choice).' }
    $heavy = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(OneDrive|Teams|ms-teams|Widgets|WidgetService|msedgewebview2|Spotify|Discord|EpicGamesLauncher|Overwolf|iCUE|ArmouryCrate|LGHUB|Razer.*|NZXT CAM)$' } | Group-Object ProcessName | ForEach-Object { $_.Name })
    if ($heavy) { Add-F 'TIP' 'Load' ("Known background RAM users running: " + ($heavy -join ', ')) 'Close or stop these from auto-starting if you do not need them while gaming. RGB/peripheral suites are common FPS/stutter culprits.' }

    return $f
}

function Show-SBReport {
    param([string]$SaveTo)
    Write-Host ''
    Write-Host '  ===== SafeBoost PC check (read-only) =====' -ForegroundColor Cyan
    $findings = Get-SBFindings
    $order = @{ BIG = 0; WARN = 1; TIP = 2; INFO = 3 }
    $colors = @{ BIG = 'Red'; WARN = 'Yellow'; TIP = 'Cyan'; INFO = 'Gray' }
    foreach ($x in ($findings | Sort-Object { $order[$_.Severity] })) {
        Write-Host ('  [{0,-4}] {1,-8} {2}' -f $x.Severity, $x.Area, $x.Finding) -ForegroundColor $colors[$x.Severity]
        if ($x.Fix) { Write-Host ('                 -> {0}' -f $x.Fix) -ForegroundColor DarkGray }
    }
    $big = @($findings | Where-Object Severity -eq 'BIG').Count
    Write-Host ''
    if ($big) { Write-Host "  $big BIG item(s) above are worth more FPS than any registry tweak. Fix those first!" -ForegroundColor Red }
    else { Write-Host '  No big hardware/driver problems found.' -ForegroundColor Green }
    if ($SaveTo) {
        $findings | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Set-Content -LiteralPath $SaveTo -Encoding UTF8
        Write-Host "  Report saved: $SaveTo" -ForegroundColor DarkGray
    }
}
