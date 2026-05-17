<#
.SYNOPSIS
    SoulwardenKioku -- one-time setup for the New World capture tool.

.DESCRIPTION
    Installs the two things a capture needs:

      * Npcap     -- the packet-capture driver
      * Wireshark -- provides the dumpcap / tshark / mergecap engines

    Run this ONCE before your first capture. Safe to re-run -- it skips
    anything already installed. The easiest way to launch it is to
    double-click Setup.cmd in the folder above.

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
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Re-launching with Administrator rights ..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
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
        return
    }
    Write-Step "Installing Npcap (silent; non-admin capture enabled) ..."
    # /admin_only=no -> ordinary users can capture without elevation later.
    $p = Start-Process -FilePath $exe `
            -ArgumentList '/S','/admin_only=no','/winpcap_mode=no','/loopback_support=no' `
            -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Err2 "Npcap installer exited with code $($p.ExitCode). Install it by hand."
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
Write-Host "  You're ready. To capture a session, double-click  SoulwardenKioku.cmd" -ForegroundColor Green
Write-Host ""
