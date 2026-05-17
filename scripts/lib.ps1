# ---------------------------------------------------------------------------
#  SoulwardenKioku -- shared helpers for the capture scripts.
#
#  Dot-sourced by setup.ps1 / capture.ps1 / sanitize.ps1:
#      . "$PSScriptRoot\lib.ps1"
# ---------------------------------------------------------------------------

# New World's Steam application id.
$script:NW_APPID = '1063730'

function Write-Step($msg)  { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  ++ $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Err2($msg)  { Write-Host "  XX $msg" -ForegroundColor Red }

function Write-Banner($title) {
    $bar = '=' * ($title.Length + 6)
    Write-Host ""
    Write-Host $bar               -ForegroundColor Magenta
    Write-Host "   $title"        -ForegroundColor Magenta
    Write-Host $bar               -ForegroundColor Magenta
    Write-Host ""
}

# Locate the Wireshark install (it provides dumpcap, tshark, mergecap,
# capinfos). Returns the directory, or $null if not found.
function Find-WiresharkDir {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Wireshark'),
        (Join-Path ${env:ProgramFiles(x86)} 'Wireshark')
    )
    foreach ($d in $candidates) {
        if ($d -and (Test-Path (Join-Path $d 'dumpcap.exe'))) { return $d }
    }
    # Fall back to the uninstall registry key.
    foreach ($hive in @('HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node')) {
        $key = Join-Path $hive 'Microsoft\Windows\CurrentVersion\Uninstall\Wireshark'
        if (Test-Path $key) {
            $loc = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallLocation
            if ($loc -and (Test-Path (Join-Path $loc 'dumpcap.exe'))) { return $loc }
        }
    }
    return $null
}

# True if the Npcap capture driver is installed.
function Test-NpcapInstalled {
    return (Test-Path "$env:SystemRoot\System32\Npcap\wpcap.dll") -or
           (Test-Path "$env:SystemRoot\System32\wpcap.dll")
}

# Steam's install directory (from the registry), or $null.
function Find-SteamPath {
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $p = (Get-ItemProperty $key -ErrorAction SilentlyContinue).SteamPath
        if (-not $p) { $p = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallPath }
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# True if New World appears to be installed in any Steam library.
function Test-NewWorldInstalled {
    $steam = Find-SteamPath
    if (-not $steam) { return $false }
    $libs = @($steam)
    $vdf  = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"' -ErrorAction SilentlyContinue |
            ForEach-Object { $libs += ($_.Matches[0].Groups[1].Value -replace '\\\\','\') }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        if (Test-Path (Join-Path $lib "steamapps\appmanifest_$($script:NW_APPID).acf")) { return $true }
    }
    return $false
}

# Path to New World's Game.log (user-local; same for every install).
function Get-GameLogPath {
    return (Join-Path $env:LOCALAPPDATA 'AGS\New World\Game.log')
}

function Get-GameLogBackupDir {
    return (Join-Path $env:LOCALAPPDATA 'AGS\New World\LogBackups')
}

# Default place to file capture sessions: Documents\SoulwardenKioku Captures.
function Get-DefaultCaptureRoot {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = $env:USERPROFILE }
    return (Join-Path $docs 'SoulwardenKioku Captures')
}
