# SafeBoost - disk cleanup
# Only caches, temp files and logs that Windows/apps recreate on their own.
# Never touches documents, downloads, browser history/passwords, game saves or shader caches
# (deleting shader caches just causes stutter while they rebuild).

$script:SBCleanupTargets = @(
    @{ Id = 'temp';     Name = 'Temporary files';                   Default = $true
       Why  = 'Leftovers from installers and apps, older than 1 day. Files in use are skipped.' }
    @{ Id = 'wucache';  Name = 'Windows Update download cache';     Default = $true
       Why  = 'Installer files of updates that are already installed. Windows re-downloads anything it still needs.' }
    @{ Id = 'docache';  Name = 'Delivery Optimization cache';       Default = $true
       Why  = 'Copies of updates kept to share with other PCs.' }
    @{ Id = 'wer';      Name = 'Error reports';                     Default = $true
       Why  = 'Crash reports waiting to be sent or already sent to Microsoft.' }
    @{ Id = 'dumps';    Name = 'Crash dumps';                       Default = $true
       Why  = 'Memory dumps written after blue screens and app crashes. Only useful to developers.' }
    @{ Id = 'logs';     Name = 'Old Windows setup & update logs';   Default = $true
       Why  = 'Log files older than 7 days from Windows setup, updates and CBS.' }
    @{ Id = 'thumbs';   Name = 'Thumbnail cache';                   Default = $false
       Why  = 'Picture/video previews in Explorer. Rebuilt automatically when you open folders (briefly slower).' }
    @{ Id = 'browser';  Name = 'Browser caches (Edge, Chrome, Brave, Opera, Firefox)'; Default = $false
       Why  = 'Cached website files only. Logins, passwords, history and bookmarks are NOT touched. Close your browsers first.' }
    @{ Id = 'recycle';  Name = 'Recycle Bin';                       Default = $false
       Why  = 'Permanently deletes everything in the Recycle Bin. Check it first!' }
    @{ Id = 'winsxs';   Name = 'Windows component store (deep clean)'; Default = $false
       Why  = 'Removes old versions of system files replaced by updates. Slow (5-15 min). Afterwards, installed updates cannot be uninstalled.' }
)

function Get-SBCleanupPaths([string]$Id) {
    $la = $env:LOCALAPPDATA
    switch ($Id) {
        'temp'    { @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) }
        'wucache' { @(Join-Path $env:SystemRoot 'SoftwareDistribution\Download') }
        'docache' { @(Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache') }
        'wer'     { @((Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'), (Join-Path $la 'Microsoft\Windows\WER')) }
        'dumps'   { @((Join-Path $env:SystemRoot 'Minidump'), (Join-Path $la 'CrashDumps'), (Join-Path $env:SystemRoot 'LiveKernelReports')) }
        'logs'    { @((Join-Path $env:SystemRoot 'Logs\CBS'), (Join-Path $env:SystemRoot 'Logs\WindowsUpdate'), (Join-Path $env:SystemRoot 'Logs\DISM')) }
        'thumbs'  { @(Join-Path $la 'Microsoft\Windows\Explorer') }
        'browser' {
            $roots = @('Microsoft\Edge\User Data', 'Google\Chrome\User Data', 'BraveSoftware\Brave-Browser\User Data', 'Vivaldi\User Data')
            $out = @()
            foreach ($r in $roots) {
                $base = Join-Path $la $r
                if (-not (Test-Path -LiteralPath $base)) { continue }
                foreach ($prof in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
                    $out += (Join-Path $prof.FullName 'Cache'), (Join-Path $prof.FullName 'Code Cache')
                }
            }
            $opera = Join-Path $la 'Opera Software'
            if (Test-Path -LiteralPath $opera) { $out += @(Get-ChildItem -LiteralPath $opera -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Cache' }) }
            $ff = Join-Path $la 'Mozilla\Firefox\Profiles'
            if (Test-Path -LiteralPath $ff) { $out += @(Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'cache2' }) }
            $out
        }
        default { @() }
    }
}

function Get-SBCleanupFiles([string]$Id) {
    $paths = @(Get-SBCleanupPaths $Id | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $files = foreach ($p in $paths) { Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue }
    switch ($Id) {
        'temp'   { $cut = (Get-Date).AddDays(-1); $files = $files | Where-Object { $_.LastWriteTime -lt $cut } }
        'logs'   { $cut = (Get-Date).AddDays(-7); $files = $files | Where-Object { $_.LastWriteTime -lt $cut -and $_.Extension -in '.log', '.cab', '.etl' } }
        'thumbs' { $files = $files | Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' } }
        'dumps'  {
            $mem = Join-Path $env:SystemRoot 'MEMORY.DMP'
            $files = @($files) + @(Get-Item -LiteralPath $mem -Force -ErrorAction SilentlyContinue)
        }
    }
    return @($files | Where-Object { $_ })
}

function Get-SBRecycleBinSize {
    try {
        $sh = New-Object -ComObject Shell.Application
        $total = 0L
        foreach ($i in $sh.Namespace(10).Items()) { $total += [long]$i.Size }
        return $total
    } catch { return 0L }
}

function Get-SBCleanupScan {
    $result = foreach ($t in $script:SBCleanupTargets) {
        $bytes = 0L; $count = 0
        switch ($t.Id) {
            'recycle' { $bytes = Get-SBRecycleBinSize }
            'docache' {
                $f = Get-SBCleanupFiles 'docache'; $bytes = [long](($f | Measure-Object Length -Sum).Sum); $count = $f.Count
            }
            'winsxs'  { $bytes = -1 }
            default   { $f = Get-SBCleanupFiles $t.Id; $bytes = [long](($f | Measure-Object Length -Sum).Sum); $count = $f.Count }
        }
        [pscustomobject]@{ Id = $t.Id; Name = $t.Name; Why = $t.Why; Default = $t.Default; Bytes = $bytes; Files = $count }
    }
    $old = Join-Path $env:SystemDrive 'Windows.old'
    $oldBytes = 0L
    if (Test-Path -LiteralPath $old) { $oldBytes = [long]((Get-ChildItem -LiteralPath $old -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }
    return [pscustomobject]@{ Targets = @($result); WindowsOldBytes = $oldBytes }
}

function Format-SBSize([long]$Bytes) {
    if ($Bytes -lt 0) { return 'Varies' }
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -gt 0)   { return '{0:N0} KB' -f [math]::Max(1, $Bytes / 1KB) }
    return '0 MB'
}

function Remove-SBFiles($Files) {
    $freed = 0L; $skipped = 0
    foreach ($f in $Files) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { $skipped++ }
    }
    return [pscustomobject]@{ Freed = $freed; Skipped = $skipped }
}

function Invoke-SBDiskCleanup {
    param([Parameter(Mandatory)][string[]]$Ids)
    $total = 0L; $n = 0
    foreach ($id in $Ids) {
        $n++
        $t = $script:SBCleanupTargets | Where-Object { $_.Id -eq $id }
        if (-not $t) { continue }
        Write-SBLog $t.Name 'STEP'
        try {
            switch ($id) {
                'recycle' {
                    $b = Get-SBRecycleBinSize
                    Clear-RecycleBin -Force -ErrorAction Stop
                    $total += $b; Write-SBLog "Emptied Recycle Bin ($(Format-SBSize $b))" 'OK'
                }
                'winsxs' {
                    Write-SBLog 'Running DISM component cleanup (5-15 minutes)...' 'INFO'
                    $out = & dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-SBLog 'Component store cleaned' 'OK' } else { Write-SBLog "DISM finished with code $LASTEXITCODE (Windows may be busy updating - try after a restart)" 'WARN' }
                }
                'docache' {
                    $before = [long]((Get-SBCleanupFiles 'docache' | Measure-Object Length -Sum).Sum)
                    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue }
                    $after = [long]((Get-SBCleanupFiles 'docache' | Measure-Object Length -Sum).Sum)
                    $total += [math]::Max(0, $before - $after); Write-SBLog "Freed $(Format-SBSize ([math]::Max(0, $before - $after)))" 'OK'
                }
                'wucache' {
                    # Pause the update services just for the delete, then put them back exactly as they were.
                    $svc = @('wuauserv', 'bits') | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -eq 'Running' }
                    foreach ($s in $svc) { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue }
                    try { $r = Remove-SBFiles (Get-SBCleanupFiles 'wucache') }
                    finally { foreach ($s in $svc) { Start-Service -Name $s.Name -ErrorAction SilentlyContinue } }
                    $total += $r.Freed; Write-SBLog "Freed $(Format-SBSize $r.Freed)$(if ($r.Skipped) { " ($($r.Skipped) files in use were skipped)" })" 'OK'
                }
                default {
                    $r = Remove-SBFiles (Get-SBCleanupFiles $id)
                    $total += $r.Freed; Write-SBLog "Freed $(Format-SBSize $r.Freed)$(if ($r.Skipped) { " ($($r.Skipped) files in use were skipped)" })" 'OK'
                }
            }
        } catch { Write-SBLog "$($t.Name): $($_.Exception.Message)" 'WARN' }
        if ($null -ne $global:SBLogQueue) { $global:SBLogQueue.Enqueue("@@P $n $($Ids.Count)") }
    }
    Write-SBLog "Total freed: $(Format-SBSize $total)" 'OK'
    return [pscustomobject]@{ Freed = $total }
}
