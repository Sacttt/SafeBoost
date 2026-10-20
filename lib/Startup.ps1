# SafeBoost - startup apps manager
# Uses the SAME switch Task Manager uses (Explorer\StartupApproved), so:
#   - nothing is deleted, the app stays installed and its Run entry stays in place
#   - Task Manager > Startup apps shows the same on/off state
#   - every change goes through Set-SBRegistry, so it is backed up and undoable

$script:SBStartupKeep = 'SecurityHealth|Windows Defender|Windows Security|Realtek|RtkAud|Synaptics|SynTP|ELAN|ETDCtrl|Waves|MaxxAudio|Nahimic|Dolby|Intel.*(Graphics|Audio|Thunderbolt)|IgfxTray|AMD (Noise|Radeon Settings)|Bluetooth|touchpad|Precision Touchpad'
$script:SBStartupSafe = 'Steam|Epic ?Games|EpicGamesLauncher|Discord|Spotify|Teams|Skype|Zoom|EADesktop|EA app|Origin|Battle\.net|Ubisoft|uplay|GOG Galaxy|Opera|MicrosoftEdgeAutoLaunch|Edge.*Auto|Google Update|GoogleDrive|Dropbox|iTunesHelper|Overwolf|CCleaner|Adobe ?(GC|Creative|Acrobat|Updater|ARM)|AdobeGCInvoker|Messenger|WhatsApp|Telegram|Cortana|uTorrent|qBittorrent|Riot|Wallpaper ?Engine|Medal|Outplayed|Copilot|PowerToys|Grammarly|Lightshot|Greenshot'

function Get-SBExeFromCommand([string]$Command) {
    if (-not $Command) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($c.StartsWith('"')) { $e = $c.IndexOf('"', 1); if ($e -gt 1) { return $c.Substring(1, $e - 1) } }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd))(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($c -split '\s+')[0]
}

function Get-SBApprovedState([string]$ApprovedKey, [string]$Name) {
    $v = Get-SBRegValue -Path $ApprovedKey -Name $Name
    if (-not $v.Exists -or -not $v.Value -or @($v.Value).Count -lt 1) { return $true }
    return ((@($v.Value)[0] % 2) -eq 0)     # 0x02/0x06 = on, 0x03/0x07 = off
}

function Get-SBStartupItems {
    $items = New-Object System.Collections.ArrayList
    $approvedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $reg = @(
        @{ Scope = 'Only you';  Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\$approvedBase\Run" }
        @{ Scope = 'All users'; Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\$approvedBase\Run" }
        @{ Scope = 'All users'; Key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approvedBase\Run32" }
    )
    foreach ($src in $reg) {
        $k = Get-Item -LiteralPath $src.Key -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $cmd = "$($k.GetValue($n))"
            [void]$items.Add([pscustomobject]@{ Name = $n; Command = $cmd; Exe = (Get-SBExeFromCommand $cmd); Scope = $src.Scope
                                                ApprovedKey = $src.Approved; ApprovedName = $n; Source = 'Registry' })
        }
    }
    $folders = @(
        @{ Scope = 'Only you';  Path = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$approvedBase\StartupFolder" }
        @{ Scope = 'All users'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$approvedBase\StartupFolder" }
    )
    $shell = $null
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            $target = $file.FullName
            if ($file.Extension -eq '.lnk') {
                try { if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }; $t = $shell.CreateShortcut($file.FullName).TargetPath; if ($t) { $target = $t } } catch { }
            }
            [void]$items.Add([pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($file.Name); Command = $target; Exe = $target; Scope = $f.Scope
                                                ApprovedKey = $f.Approved; ApprovedName = $file.Name; Source = 'Startup folder' })
        }
    }
    foreach ($i in $items) {
        $desc = $null; $pub = $null
        if ($i.Exe -and (Test-Path -LiteralPath $i.Exe -ErrorAction SilentlyContinue)) {
            try { $vi = (Get-Item -LiteralPath $i.Exe -ErrorAction Stop).VersionInfo; $desc = $vi.FileDescription; $pub = $vi.CompanyName } catch { }
        }
        $text = "$($i.Name) $desc $pub $($i.Exe)"
        $tag = if ($text -match $script:SBStartupKeep) { 'Keep' } elseif ($text -match $script:SBStartupSafe) { 'Safe to disable' } else { '' }
        $i | Add-Member -NotePropertyName Description -NotePropertyValue $(if ($desc) { $desc.Trim() } else { $i.Name }) -Force
        $i | Add-Member -NotePropertyName Publisher -NotePropertyValue $(if ($pub) { $pub.Trim() } else { 'Unknown publisher' }) -Force
        $i | Add-Member -NotePropertyName Enabled -NotePropertyValue (Get-SBApprovedState $i.ApprovedKey $i.ApprovedName) -Force
        $i | Add-Member -NotePropertyName Tag -NotePropertyValue $tag -Force
        $i | Add-Member -NotePropertyName CanDisable -NotePropertyValue ($text -notmatch 'SecurityHealth|Windows Security') -Force
        $i | Add-Member -NotePropertyName Key -NotePropertyValue "$($i.ApprovedKey)|$($i.ApprovedName)" -Force
    }
    return @($items | Sort-Object @{ e = { -not $_.Enabled } }, Description)
}

function Set-SBStartupItem {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][bool]$Enable)
    if (-not $Enable -and -not $Item.CanDisable) { Write-SBLog "$($Item.Description) is part of Windows Security - leaving it on" 'WARN'; return $false }
    $bytes = if ($Enable) { [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
             else { [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([long](Get-Date).ToFileTime())) }
    Write-SBLog "$(if ($Enable) { 'Enable' } else { 'Disable' }) at startup: $($Item.Description)" 'STEP'
    return (Set-SBRegistry -Path $Item.ApprovedKey -Name $Item.ApprovedName -Type Binary -Value $bytes -TweakId "startup:$($Item.Name)")
}
