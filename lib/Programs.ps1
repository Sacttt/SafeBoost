# SafeBoost - installed (desktop) programs
# Lists normal Win32 programs with their size so you can uninstall what you don't use.
# SafeBoost never uninstalls these silently: the program's own uninstaller is opened.

# Drivers, runtimes and system pieces other programs depend on: listed but no Uninstall button.
$script:SBProgramKeep = 'Visual C\+\+|\.NET|Windows Desktop Runtime|ASP\.NET|DirectX|WebView2|Microsoft Edge|Windows SDK|Windows Driver|Update Health|PC Health Check|Microsoft Update|Windows Subsystem|' +
    'NVIDIA (Graphics Driver|PhysX|HD Audio|USBC|FrameView SDK)|NVIDIA App|AMD (Chipset|Software|Radeon|Ryzen)|Realtek|Intel\(R\) (Management|Chipset|Graphics|Wireless|Rapid|Serial|Dynamic|Optane)|Intel.*Driver|' +
    'Synaptics|ELAN|Dolby|Waves|Thunderbolt|Bluetooth|Vulkan|OpenAL|Steamworks Common|EasyAntiCheat|BattlEye|Riot Vanguard|FACEIT AC|Java\(TM\)|Python Launcher'

# Commonly preinstalled trialware / promos people usually want gone.
$script:SBProgramUnwanted = '^McAfee|^Norton|WildTangent|ExpressVPN|Booking\.com|Dropbox (25|Promotion|Update Helper)|^Microsoft 365 - [a-z]{2}-[a-z]{2}$|^Microsoft OneNote - [a-z]{2}-[a-z]{2}$|' +
    'CyberLink (Power2Go|PowerDVD|YouCam|PhotoDirector|PowerDirector) .*(Essential|Trial)|HP (Sure|Wolf|Support Assistant|Documentation|JumpStart)|Dell (SupportAssist Remediation|Digital Delivery)|' +
    'Lenovo (Now|Welcome|Vantage Service)|Acer (Jumpstart|Care Center|Collection)|ASUS (GiftBox|Welcome)|Amazon Assistant|^Avast Free|^AVG |Ask Toolbar|Candy Crush|^Keeper|Trend Micro'

function Get-SBInstalledPrograms {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $seen = @{}
    $list = foreach ($r in $roots) {
        foreach ($k in Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName -or -not $p.UninstallString) { continue }
            if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -in 'Update', 'Hotfix', 'Security Update') { continue }
            $name = "$($p.DisplayName)".Trim()
            if ($seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            $bytes = if ($p.EstimatedSize) { [long]$p.EstimatedSize * 1KB } else { 0L }
            $icon = $null
            if ($p.DisplayIcon) { $icon = ("$($p.DisplayIcon)" -replace ',-?\d+$', '').Trim('"') }
            $date = $null
            if ($p.InstallDate -match '^\d{8}$') { try { $date = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null) } catch { } }
            [pscustomobject]@{
                Name      = $name
                Publisher = $(if ($p.Publisher) { "$($p.Publisher)".Trim() } else { '' })
                Version   = "$($p.DisplayVersion)"
                Bytes     = $bytes
                Installed = $date
                Icon      = $icon
                Uninstall = "$($p.UninstallString)"
                Keep      = ($name -match $script:SBProgramKeep)
                Unwanted  = ($name -match $script:SBProgramUnwanted)
            }
        }
    }
    return @($list | Sort-Object @{ e = { -not $_.Unwanted } }, @{ e = { $_.Bytes }; Descending = $true })
}

function Start-SBUninstall {
    # Opens the program's own uninstaller (interactive) - nothing is removed silently.
    param([Parameter(Mandatory)]$Program)
    if ($Program.Keep) { throw "$($Program.Name) is a driver/runtime that other software needs." }
    $u = $Program.Uninstall.Trim()
    if ($u -match '^(?i)msiexec(\.exe)?\s+.*?(\{[0-9A-F-]{36}\})') {
        Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $($Matches[2])"
    } else {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$u`"" -WindowStyle Hidden
    }
}
