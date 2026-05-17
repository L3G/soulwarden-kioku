<#
.SYNOPSIS
    SoulwardenKioku -- one-time setup for the New World capture tool.

.DESCRIPTION
    Installs the two things a capture needs:

      * Npcap     -- the packet-capture driver
      * Wireshark -- provides the dumpcap / tshark / mergecap engines

    SoulwardenKioku.cmd runs this automatically the first time it cannot
    find the capture engine. Safe to re-run -- it skips anything already
    installed.

.NOTES
    Self-elevates to Administrator (Npcap installs a kernel driver).
    Run it from the machine's own desktop, not over Remote Desktop with
    a half-open session -- the Npcap driver install wants a real desktop.
#>
[CmdletBinding()]
param(
    [string]$NpcapVersion = '1.88'
)

# --- self-elevate -----------------------------------------------------------
#  Installing the Npcap driver needs Administrator rights. Without them,
#  relaunch elevated and WAIT, so the caller (SoulwardenKioku.cmd) can
#  re-check and carry on once the install has finished.
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "  Installing the capture engine needs Administrator rights." -ForegroundColor Yellow
    Write-Host "  Windows will now ask for permission -- please click Yes." -ForegroundColor Yellow
    try {
        Start-Process powershell -Verb RunAs -Wait `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } catch {
        Write-Host "  Permission was declined -- the capture engine was not installed." -ForegroundColor Red
        Write-Host "  Re-run SoulwardenKioku and click Yes, or install Wireshark and" -ForegroundColor Red
        Write-Host "  Npcap by hand from wireshark.org and npcap.com." -ForegroundColor Red
    }
    return
}

. "$PSScriptRoot\lib.ps1"

$ProgressPreference    = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Write-Banner 'SoulwardenKioku capture-tool setup'

# --- 1. Npcap ---------------------------------------------------------------
if (Test-NpcapInstalled) {
    Write-Ok "Npcap is already installed."
} else {
    $url = "https://npcap.com/dist/npcap-$NpcapVersion.exe"
    $exe = Join-Path $env:TEMP "npcap-$NpcapVersion.exe"
    Write-Step "Downloading Npcap $NpcapVersion from npcap.com ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $exe
    } catch {
        Write-Err2 "Could not download Npcap automatically."
        Write-Err2 "Install it by hand from https://npcap.com/#download , then re-run setup."
        Read-Host "  Press Enter to close this window"
        return
    }
    Write-Step "Installing Npcap (silent; non-admin capture enabled) ..."
    # /admin_only=no -> ordinary users can capture without elevation later.
    $p = Start-Process -FilePath $exe `
            -ArgumentList '/S','/admin_only=no','/winpcap_mode=no','/loopback_support=no' `
            -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Err2 "Npcap installer exited with code $($p.ExitCode). Install it by hand."
        Read-Host "  Press Enter to close this window"
        return
    }
    Write-Ok "Npcap installed."
}

# --- 2. Wireshark (dumpcap / tshark / mergecap / capinfos) ------------------
$wsDir = Find-WiresharkDir
if ($wsDir) {
    Write-Ok "Wireshark is already installed ($wsDir)."
} else {
    $haveWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if ($haveWinget) {
        Write-Step "Installing Wireshark via winget ..."
        & winget install --id WiresharkFoundation.Wireshark -e --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
    $wsDir = Find-WiresharkDir
    if (-not $wsDir) {
        Write-Err2 "Wireshark is not installed."
        Write-Err2 "Install it from https://www.wireshark.org/download.html and re-run setup."
        Read-Host "  Press Enter to close this window"
        return
    }
    Write-Ok "Wireshark installed ($wsDir)."
}

# --- 3. New World present? (warning only) -----------------------------------
if (Test-NewWorldInstalled) {
    Write-Ok "New World was found in your Steam library."
} else {
    Write-Warn2 "New World was not detected in a Steam library."
    Write-Warn2 "That's fine if it's installed elsewhere -- the capture launches"
    Write-Warn2 "the game through Steam regardless. Just make sure it runs first."
}

# --- 4. Verify --------------------------------------------------------------
Write-Step "Verifying the capture engine ..."
$dumpcap = Join-Path $wsDir 'dumpcap.exe'
& $dumpcap --version | Select-Object -First 1
Write-Host ""
Write-Host "  Network interfaces the capture engine can see:" -ForegroundColor Cyan
& $dumpcap -D

Write-Banner 'Setup complete'
Write-Host "  The capture engine is installed -- SoulwardenKioku will continue." -ForegroundColor Green
Write-Host ""
# This elevated window is separate from the launcher; pause so the result is
# readable, then close it -- the launcher carries on where it left off.
Read-Host "  Press Enter to close this setup window"
