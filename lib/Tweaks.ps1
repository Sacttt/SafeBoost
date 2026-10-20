# SafeBoost - tweak catalog
# Each tweak is plain data. The engine in Core.ps1 applies it and records the old values.
#
# Fields:
#   Id, Category, Name, Why        - what it is and why it helps
#   Presets                        - which presets include it: Safe, Gaming, Max (empty = Custom menu only)
#   MinBuild / MaxBuild            - Windows build limits (Win11 = 22000+)
#   Reboot                         - needs a restart to fully apply
#   Registry                       - @{ Path; Name; Type; Value }   (Value may be a scriptblock that gets the current value)
#   Services                       - @{ Name; Mode = 'demand'|'disabled'; Stop = $true }
#   Tasks                          - @{ Path; Name }
#   Action                         - name of a special engine action (PowerPlan, Cleanup)
#
# Deliberately NOT included (they are placebo, risky, or break things):
#   - Disabling Windows Update, Defender, SmartScreen, UAC, Spectre/Meltdown mitigations, or the firewall
#   - bcdedit tweaks (disabledynamictick, useplatformclock, tscsyncpolicy...) - placebo at best, boot problems at worst
#   - "NetworkThrottlingIndex", TCP "Nagle" hacks, RAM "cleaners", timer-resolution services - no measurable FPS gain
#   - Disabling SysMain/Search indexing, deleting shader caches, removing Edge/WebView2/Store/Xbox services

$script:SBTweaks = @(

    # ============================================================ PRIVACY & BACKGROUND JUNK
    @{ Id='telemetry'; Category='Privacy'; Name='Reduce telemetry to the minimum'
       Why='Stops the Connected User Experiences service and its CEIP/feedback tasks from running in the background.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='DoNotShowFeedbackNotifications'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Microsoft\Siuf\Rules'; Name='NumberOfSIUFInPeriod'; Type='DWord'; Value=0 }
       )
       Services=@( @{ Name='DiagTrack'; Mode='disabled'; Stop=$true }, @{ Name='dmwappushservice'; Mode='demand' } )
       Tasks=@(
         @{ Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='Consolidator' }
         @{ Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='UsbCeip' }
         @{ Path='\Microsoft\Windows\Application Experience\'; Name='ProgramDataUpdater' }
         @{ Path='\Microsoft\Windows\Feedback\Siuf\'; Name='DmClient' }
         @{ Path='\Microsoft\Windows\Feedback\Siuf\'; Name='DmClientOnScenarioDownload' }
       ) }

    @{ Id='ads'; Category='Privacy'; Name='Disable advertising ID & tailored experiences'
       Why='No ad tracking ID, no "personalised" tips based on diagnostic data.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name='DisabledByGroupPolicy'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name='TailoredExperiencesWithDiagnosticDataEnabled'; Type='DWord'; Value=0 }
       ) }

    @{ Id='activity'; Category='Privacy'; Name='Disable activity history'
       Why='Windows stops logging and uploading what apps/files you open.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='PublishUserActivities'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='UploadUserActivities'; Type='DWord'; Value=0 }
       ) }

    @{ Id='suggestions'; Category='Privacy'; Name='Kill ads, tips, "suggestions" and silent app installs'
       Why='Stops Windows from auto-installing sponsored apps (Candy Crush etc.) and showing ads in Start, Settings, lock screen and Explorer.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SilentInstalledAppsEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='PreInstalledAppsEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='OemPreInstalledAppsEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SystemPaneSuggestionsEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SoftLandingEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='RotatingLockScreenOverlayEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338387Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338388Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338389Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338393Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353694Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353696Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name='ScoobeSystemSettingEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSyncProviderNotifications'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_IrisRecommendations'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Type='DWord'; Value=1 }
       ) }

    @{ Id='websearch'; Category='Privacy'; Name='Remove Bing web results from Start search'
       Why='Start menu search becomes local-only: faster and no keystrokes sent to Bing.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name='BingSearchEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name='CortanaConsent'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name='DisableSearchBoxSuggestions'; Type='DWord'; Value=1 }
       ) }

    @{ Id='ai'; Category='Privacy'; Name='Turn off Copilot & Recall snapshots'
       Why='Stops the Copilot sidebar and Recall screenshot indexing (Recall uses CPU, disk and NPU in the background).'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Type='DWord'; Value=1 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowCopilotButton'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Type='DWord'; Value=1 }
       ) }

    @{ Id='widgets'; Category='Background'; Name='Disable Widgets / News & Interests'
       Why='Widgets keep a WebView process alive and pull news in the background (~100-300 MB RAM).'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name='AllowNewsAndInterests'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name='EnableFeeds'; Type='DWord'; Value=0 }
       ) }

    @{ Id='edgebg'; Category='Background'; Name='Stop Edge running in the background'
       Why='Edge "Startup boost" and background mode keep Edge processes in RAM even when closed. Edge itself is NOT removed. (Edge will show "managed by your organization" - that is just this setting.)'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='StartupBoostEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='BackgroundModeEnabled'; Type='DWord'; Value=0 }
       ) }

    @{ Id='p2pupdates'; Category='Background'; Name='Stop uploading Windows Updates to other PCs'
       Why='Delivery Optimization can use your upload bandwidth to seed updates to strangers - bad for ping. Updates still download normally.'
       Presets=@('Safe','Gaming','Max')
       Registry=@( @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name='DODownloadMode'; Type='DWord'; Value=0 } ) }

    @{ Id='startupdelay'; Category='Responsiveness'; Name='Remove the artificial startup-app delay'
       Why='Windows waits before launching startup apps; removing it makes the desktop usable sooner.'
       Presets=@('Safe','Gaming','Max')
       Registry=@( @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name='StartupDelayInMSec'; Type='DWord'; Value=0 } ) }

    @{ Id='cleanup'; Category='Cleanup'; Name='Clean temp files & update delivery cache'
       Why='Deletes temp files older than 2 days and the Delivery Optimization cache. Never touches your documents, downloads or recycle bin.'
       Presets=@('Safe','Gaming','Max'); Action='Cleanup' }

    # ============================================================ GAMING
    @{ Id='gamemode'; Category='Gaming'; Name='Make sure Game Mode is ON'
       Why='Game Mode stops Windows Update from installing drivers/restarting and prioritises the game. Some "optimizers" wrongly turn it off.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\GameBar'; Name='AutoGameModeEnabled'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Microsoft\GameBar'; Name='AllowAutoGameMode'; Type='DWord'; Value=1 }
       ) }

    @{ Id='gamedvr'; Category='Gaming'; Name='Disable background game recording (Game DVR)'
       Why='Background recording constantly encodes your last minutes of gameplay - a real FPS cost on weaker GPUs. Game Bar still opens with Win+G.'
       Presets=@('Safe','Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\System\GameConfigStore'; Name='GameDVR_Enabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name='AppCaptureEnabled'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name='HistoricalCaptureEnabled'; Type='DWord'; Value=0 }
       ) }

    @{ Id='powerplan'; Category='Gaming'; Name='High-performance power plan (plugged in)'
       Why='Keeps CPU clocks up instead of parking cores and stops USB/PCIe power saving that causes micro-stutter and input lag. Battery settings untouched.'
       Presets=@('Gaming','Max'); Action='PowerPlan' }

    @{ Id='hags'; Category='Gaming'; Name='Hardware-accelerated GPU scheduling'
       Why='Lets the GPU manage its own memory queue - lower latency on modern GPUs (GTX 10-series / RX 5000 and newer). Ignored safely by older GPUs. Required for DLSS Frame Generation.'
       Presets=@('Gaming','Max'); MinBuild=19041; Reboot=$true
       Registry=@( @{ Path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name='HwSchMode'; Type='DWord'; Value=2 } ) }

    @{ Id='windowedopt'; Category='Gaming'; Name='Optimizations for windowed & borderless games'
       Why='Windows 11 feature: borderless DX10/11 games get the same low-latency flip model as fullscreen (enables VRR + Auto HDR in windowed).'
       Presets=@('Gaming','Max'); MinBuild=22000
       Registry=@( @{ Path='HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; Name='DirectXUserGlobalSettings'; Type='String'
                     Value={ param($cur) $s = "$cur"; if ($s -match 'SwapEffectUpgradeEnable=\d') { $s -replace 'SwapEffectUpgradeEnable=\d', 'SwapEffectUpgradeEnable=1' } else { $s + 'SwapEffectUpgradeEnable=1;' } } } ) }

    @{ Id='mmcss'; Category='Gaming'; Name='Prioritise games in the multimedia scheduler'
       Why='Gives the "Games" scheduler class high CPU/GPU/IO priority and reserves less CPU for background multimedia (20% -> 10%).'
       Presets=@('Gaming','Max')
       Registry=@(
         @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='SystemResponsiveness'; Type='DWord'; Value=10 }
         @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='GPU Priority'; Type='DWord'; Value=8 }
         @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='Priority'; Type='DWord'; Value=6 }
         @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='Scheduling Category'; Type='String'; Value='High' }
         @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='SFIO Priority'; Type='String'; Value='High' }
       ) }

    @{ Id='mouseaccel'; Category='Gaming'; Name='Turn off mouse acceleration ("Enhance pointer precision")'
       Why='1:1 raw mouse movement - consistent aim. Takes effect after sign-out.'
       Presets=@('Gaming','Max')
       Registry=@(
         @{ Path='HKCU:\Control Panel\Mouse'; Name='MouseSpeed'; Type='String'; Value='0' }
         @{ Path='HKCU:\Control Panel\Mouse'; Name='MouseThreshold1'; Type='String'; Value='0' }
         @{ Path='HKCU:\Control Panel\Mouse'; Name='MouseThreshold2'; Type='String'; Value='0' }
       ) }

    @{ Id='stickykeys'; Category='Gaming'; Name='Stop the Sticky Keys popup when you spam Shift'
       Why='Pressing Shift 5 times mid-game no longer alt-tabs you out to a popup. Sticky Keys itself still works from Settings.'
       Presets=@('Gaming','Max')
       Registry=@( @{ Path='HKCU:\Control Panel\Accessibility\StickyKeys'; Name='Flags'; Type='String'; Value='506' } ) }

    # ============================================================ MAX
    @{ Id='visualfx'; Category='Max'; Name='Lean visual effects (keep smooth fonts & thumbnails)'
       Why='Turns off transparency, window min/max animation, taskbar animation and Aero Peek. Helps low-end GPUs/iGPUs; barely noticeable on strong PCs.'
       Presets=@('Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name='VisualFXSetting'; Type='DWord'; Value=3 }
         @{ Path='HKCU:\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Type='String'; Value='0' }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAnimations'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\DWM'; Name='EnableAeroPeek'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Type='DWord'; Value=0 }
         @{ Path='HKCU:\Control Panel\Desktop'; Name='MenuShowDelay'; Type='String'; Value='200' }
       ) }

    @{ Id='bgapps'; Category='Max'; Name='Block Store apps from running in the background'
       Why='Store apps (Mail, Phone Link, etc.) stop waking up in the background. Downside: those apps only update/notify while open.'
       Presets=@('Max')
       Registry=@(
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name='GlobalUserDisabled'; Type='DWord'; Value=1 }
         @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name='BackgroundAppGlobalToggle'; Type='DWord'; Value=0 }
       ) }

    @{ Id='mapsbroker'; Category='Max'; Name='Downloaded-maps service on demand only'
       Why='The offline maps manager no longer starts at boot. It still starts automatically if the Maps app needs it.'
       Presets=@('Max')
       Services=@( @{ Name='MapsBroker'; Mode='demand' } ) }

    # ============================================================ QUALITY OF LIFE (Custom only)
    @{ Id='fileext'; Category='Extras'; Name='Show file extensions'
       Why='See ".exe" vs ".pdf" - also a security win (spot fake "photo.jpg.exe" files).'
       Presets=@()
       Registry=@( @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='HideFileExt'; Type='DWord'; Value=0 } ) }

    @{ Id='endtask'; Category='Extras'; Name='Add "End task" to taskbar right-click (Win11)'
       Why='Force-close a frozen game straight from the taskbar.'
       Presets=@(); MinBuild=22631
       Registry=@( @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name='TaskbarEndTask'; Type='DWord'; Value=1 } ) }

    @{ Id='classicmenu'; Category='Extras'; Name='Classic right-click menu (Win11)'
       Why='Brings back the full Windows 10 context menu without "Show more options". Restart Explorer or sign out to see it.'
       Presets=@(); MinBuild=22000
       Registry=@( @{ Path='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Name='(default)'; Type='String'; Value='' } ) }
)

function Get-SBTweaks {
    param([string]$Preset)
    $build = Get-SBWindowsBuild
    $list = foreach ($t in $script:SBTweaks) {
        $obj = [pscustomobject]$t
        $ok = $true
        if ($t.MinBuild -and $build -lt $t.MinBuild) { $ok = $false }
        if ($t.MaxBuild -and $build -gt $t.MaxBuild) { $ok = $false }
        $obj | Add-Member -NotePropertyName Supported -NotePropertyValue $ok -Force
        $obj
    }
    if ($Preset) { return @($list | Where-Object { $_.Supported -and ($_.Presets -contains $Preset) }) }
    return @($list)
}

function Invoke-SBCleanup {
    param([string]$TweakId)
    $targets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Select-Object -Unique
    $cutoff = (Get-Date).AddDays(-2)
    $freed = 0L
    foreach ($dir in $targets) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
        foreach ($f in $files) {
            if ($script:SB.DryRun) { $freed += $f.Length; continue }
            try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }  # in-use files are skipped
        }
    }
    if (-not $script:SB.DryRun -and (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { }
    }
    $mb = [math]::Round($freed / 1MB, 1)
    if ($script:SB.DryRun) { Write-SBLog "Would free about $mb MB of temp files" 'DRY'; return }
    Add-SBChange @{ Kind = 'Info'; TweakId = $TweakId; Name = 'Cleanup'; FreedMB = $mb }
    Write-SBLog "Cleaned $mb MB of old temp files" 'OK'
}

function Invoke-SBTweak {
    param([Parameter(Mandatory)]$Tweak)
    Write-SBLog "$($Tweak.Name)" 'STEP'
    if (-not $Tweak.Supported) { Write-SBLog 'Not supported on this Windows version - skipped' 'SKIP'; return }
    foreach ($r in @($Tweak.Registry)) {
        if (-not $r) { continue }
        [void](Set-SBRegistry -Path $r.Path -Name $r.Name -Type $r.Type -Value $r.Value -TweakId $Tweak.Id)
    }
    foreach ($s in @($Tweak.Services)) {
        if (-not $s) { continue }
        [void](Set-SBService -Name $s.Name -StartMode $s.Mode -StopNow:([bool]$s.Stop) -TweakId $Tweak.Id)
    }
    foreach ($t in @($Tweak.Tasks)) {
        if (-not $t) { continue }
        [void](Disable-SBTask -TaskPath $t.Path -TaskName $t.Name -TweakId $Tweak.Id)
    }
    switch ($Tweak.Action) {
        'PowerPlan' { [void](Set-SBPowerPlan -TweakId $Tweak.Id) }
        'Cleanup'   { Invoke-SBCleanup -TweakId $Tweak.Id }
    }
}
