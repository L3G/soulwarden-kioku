<#
.SYNOPSIS
    SoulwardenKioku -- New World network-capture launcher.

    One run = one play session. It starts a passive packet capture,
    launches New World normally through Steam, lets you drop timestamped
    notes while you play, then -- when you finish -- builds a privacy-safe
    bundle you can share with the protocol-research community.

.DESCRIPTION
    Easiest way to run this is to double-click SoulwardenKioku.cmd in the folder
    above. From PowerShell, pass -Label to tag the session.

    What it does, and does NOT do:
      * It is a PASSIVE network capture. New World's game traffic is
        DTLS-encrypted, so payloads are not readable. What a capture
        gives the project is packet timing, sizes, direction, the
        server endpoints, and the DTLS handshake.
      * It launches the game NORMALLY through Steam + EasyAntiCheat.
        Nothing is injected, hooked, or modified. The capture tool only
        watches your own network adapter -- there is no ban risk.

    Each run creates a session folder:
        <CaptureRoot>\<yyyyMMdd_HHmmss>_<label>\
            pcap\        the raw capture (stays on your machine)
            Game.log     New World's log for this session
            session.md   metadata (build, server IPs, interface)
            notes.md     your timestamped in-game event markers
        ...and a shareable  <session>_soulwardenkioku.zip  built by sanitize.ps1.

.PARAMETER Label
    Short tag for this session, e.g. "char-create", "msq-windsward".

.PARAMETER Watch
    Open the Wireshark GUI to watch packets live instead of the headless
    engine. Stop the capture in the GUI before typing 'stop'.

.PARAMETER NoGame
    Capture only -- do not launch New World (e.g. it is already running).

.PARAMETER AllTraffic
    Capture TCP as well as UDP (picks up the HTTPS login flow). Default is
    UDP-only -- that is the actual game protocol.

.PARAMETER NoSanitize
    Skip building the shareable bundle at the end. Run sanitize.ps1 by
    hand later if you change your mind.

.PARAMETER ListInterfaces
    Print the capture interfaces and exit.

.EXAMPLE
    .\capture.ps1 -Label char-create
.EXAMPLE
    .\capture.ps1 -Label msq-everfall -AllTraffic
#>
[CmdletBinding()]
param(
    [string]$Label        = 'session',
    [string]$CaptureRoot  = '',
    [int]   $IfIndex      = 0,
    [string]$Interface    = '',
    [int]   $RingMB       = 200,
    [switch]$Watch,
    [switch]$NoGame,
    [switch]$AllTraffic,
    [switch]$NoSanitize,
    [switch]$ListInterfaces
)

. "$PSScriptRoot\lib.ps1"

# --------------------------------------------------------------------------
#  Preflight -- make sure the capture engine is installed. The first time
#  SoulwardenKioku runs (or if Wireshark / Npcap was removed) this installs
#  it automatically: setup.ps1 self-elevates, installs, and we wait for it.
# --------------------------------------------------------------------------
if (-not (Find-WiresharkDir) -or -not (Test-NpcapInstalled)) {
    Write-Banner 'First-time setup'
    Write-Host "  SoulwardenKioku needs its capture engine (Npcap + Wireshark)."
    Write-Host "  This installs once. Windows will ask for permission -- click Yes."
    Write-Host ""
    & "$PSScriptRoot\setup.ps1"
    if (-not (Find-WiresharkDir) -or -not (Test-NpcapInstalled)) {
        Write-Err2 "The capture engine is still missing -- setup did not finish."
        Write-Err2 "See the messages above. You can also install Wireshark and Npcap"
        Write-Err2 "by hand from wireshark.org and npcap.com, then run this again."
        Read-Host "Press Enter to close"
        return
    }
    Write-Ok "Capture engine ready."
    Write-Host ""
}
$wsDir = Find-WiresharkDir

$Dumpcap   = Join-Path $wsDir 'dumpcap.exe'
$Wireshark = Join-Path $wsDir 'Wireshark.exe'
$GameLog   = Get-GameLogPath
$LogBackup = Get-GameLogBackupDir

if ($ListInterfaces) { & $Dumpcap -D; return }

if (-not $CaptureRoot) { $CaptureRoot = Get-DefaultCaptureRoot }

# Capture device -> dumpcap NPF name. Auto-detect via the default route.
function Resolve-CaptureDevice {
    if ($Interface) { return $Interface }
    $idx = $IfIndex
    if ($idx -le 0) {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                 Sort-Object RouteMetric, ifMetric | Select-Object -First 1
        if (-not $route) {
            throw "No default network route found. Pass -IfIndex (see -ListInterfaces)."
        }
        $idx = $route.ifIndex
    }
    $ad = Get-NetAdapter -InterfaceIndex $idx -ErrorAction Stop
    if ($ad.Status -ne 'Up') { Write-Warn2 "Adapter '$($ad.Name)' status is $($ad.Status)." }
    Write-Ok "Capture interface: [$idx] $($ad.Name) -- $($ad.InterfaceDescription)"
    return "\Device\NPF_$($ad.InterfaceGuid)"
}

$device = Resolve-CaptureDevice

if (-not (Test-NewWorldInstalled) -and -not $NoGame) {
    Write-Warn2 "New World was not detected in a Steam library -- will still try"
    Write-Warn2 "to launch it through Steam. Use -NoGame if you launch it yourself."
}

# --------------------------------------------------------------------------
#  Session folder
# --------------------------------------------------------------------------
$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeLabel  = ($Label -replace '[^\w.\-]', '_')
$sessionDir = Join-Path $CaptureRoot ("{0}_{1}" -f $stamp, $safeLabel)
$pcapDir    = Join-Path $sessionDir 'pcap'
New-Item -ItemType Directory -Force -Path $pcapDir | Out-Null

$pcapBase   = Join-Path $pcapDir 'nw.pcapng'
$notesFile  = Join-Path $sessionDir 'notes.md'
$sessionMd  = Join-Path $sessionDir 'session.md'
$dumpcapLog = Join-Path $sessionDir 'dumpcap.log'

# Capture filter: drop chatty LAN/infra noise; keep the game traffic.
$noisePorts = '53','5353','5355','1900','137','138','67','68','123'
$noiseExpr  = ($noisePorts | ForEach-Object { "port $_" }) -join ' or '
$filter     = if ($AllTraffic) { "not ($noiseExpr)" } else { "udp and not ($noiseExpr)" }

# --------------------------------------------------------------------------
#  Start the capture
# --------------------------------------------------------------------------
Write-Banner 'SoulwardenKioku -- New World network capture'
Write-Host "  Session : $stamp`_$safeLabel"
Write-Host "  Folder  : $sessionDir"
Write-Host "  Filter  : $filter"
Write-Host "  Mode    : $(if ($Watch) {'Wireshark GUI'} else {'headless dumpcap'})"
Write-Host ""

$ringArgs = @('-b', "filesize:$($RingMB * 1024)")   # split by size; never wraps/deletes

if ($Watch) {
    Write-Step "Launching Wireshark (live view) ..."
    $wsArgs  = @('-i', $device, '-k', '-w', $pcapBase, '-f', $filter) + $ringArgs
    $capProc = Start-Process -FilePath $Wireshark -ArgumentList $wsArgs -PassThru
} else {
    Write-Step "Starting the capture engine (dumpcap) ..."
    $dcArgs  = @('-i', $device, '-f', $filter, '-w', $pcapBase, '-n') + $ringArgs
    $capProc = Start-Process -FilePath $Dumpcap -ArgumentList $dcArgs -PassThru -NoNewWindow `
                   -RedirectStandardError $dumpcapLog
    Start-Sleep -Seconds 2
    if ($capProc.HasExited) {
        Write-Err2 "dumpcap exited immediately -- see $dumpcapLog"
        if (Test-Path $dumpcapLog) { Get-Content $dumpcapLog | Select-Object -Last 10 }
        return
    }
    Write-Ok "Capturing (PID $($capProc.Id)) -> $pcapBase"
}

# --------------------------------------------------------------------------
#  Session metadata stub
# --------------------------------------------------------------------------
@"
# New World capture session

- session     : $stamp`_$safeLabel
- started     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- label       : $Label
- capture     : pcap/ (DTLS-encrypted UDP -- payloads not decoded)
- bpf filter  : ``$filter``
- game build  : (filled in when the session ends)
- server IPs  : (filled in when the session ends)

## Character / context  --  please fill this in

- character   : <class, level -- no need to give the name>
- region/world: <e.g. us-east, Valhalla>
- intent      : <what part of the game this session covers>

## Notes

See notes.md for timestamped in-game event markers.
Anything unusual this session:

"@ | Set-Content -LiteralPath $sessionMd -Encoding UTF8

"# In-game event markers -- $stamp`_$safeLabel`n" | Set-Content -LiteralPath $notesFile -Encoding UTF8

# --------------------------------------------------------------------------
#  Launch the game
# --------------------------------------------------------------------------
if (-not $NoGame) {
    Write-Step "Launching New World via Steam (normal launch -- EAC, no injection) ..."
    Start-Process "steam://rungameid/$NW_APPID"
} else {
    Write-Warn2 "-NoGame set: not launching the game."
}

# --------------------------------------------------------------------------
#  Marker loop -- runs until you type 'stop'
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "  Capture is running. While you play:" -ForegroundColor Green
Write-Host "    * type a short note + Enter to drop a timestamped marker" -ForegroundColor Green
Write-Host "      (entered world, first quest, zone change, combat, disconnect ...)" -ForegroundColor Green
Write-Host "    * type 'stop' + Enter when you finish the session" -ForegroundColor Green
Write-Host ""

try {
    while ($true) {
        $line = Read-Host 'marker'
        if ($null -eq $line) { continue }
        $t = $line.Trim()
        if ($t -in @('stop','q','quit','exit')) { break }
        if ($t) {
            $entry = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t
            Add-Content -LiteralPath $notesFile -Value $entry -Encoding UTF8
            Write-Host "  logged: $entry" -ForegroundColor DarkGray
        }
    }
}
finally {
    # ----------------------------------------------------------------------
    #  Stop + collect
    # ----------------------------------------------------------------------
    Write-Host ""
    Write-Step "Ending capture session ..."

    if ($Watch) {
        Write-Warn2 "Watch mode: stop the capture in Wireshark (red square) and save if asked."
    } elseif ($capProc -and -not $capProc.HasExited) {
        try { Stop-Process -Id $capProc.Id -Force -ErrorAction Stop } catch { }
        Start-Sleep -Seconds 1
        Write-Ok "Capture engine stopped."
    }

    # Copy Game.log (best-effort; the game may still hold it open).
    function Copy-Possibly-Locked($src, $dst) {
        if (-not (Test-Path $src)) { return $false }
        try { Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop; return $true }
        catch {
            try {
                $in  = [System.IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
                $out = [System.IO.File]::Create($dst)
                $in.CopyTo($out); $out.Close(); $in.Close(); return $true
            } catch { Write-Warn2 "Could not copy $src"; return $false }
        }
    }

    if (Copy-Possibly-Locked $GameLog (Join-Path $sessionDir 'Game.log')) {
        Write-Ok "Game.log copied."
    } else {
        Write-Warn2 "Game.log not found -- session.md will lack the build/server info."
    }
    # Safety net: also grab the newest rotated log.
    if (Test-Path $LogBackup) {
        $lastBackup = Get-ChildItem $LogBackup -Filter '*.log' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastBackup) {
            Copy-Possibly-Locked $lastBackup.FullName `
                (Join-Path $sessionDir ('GameLog-backup_' + $lastBackup.Name)) | Out-Null
        }
    }

    # Pull build + server IPs out of the copied log for session.md.
    $copiedLog = Join-Path $sessionDir 'Game.log'
    $build = ''
    $serverIps = @()
    if (Test-Path $copiedLog) {
        $buildLine = Select-String -LiteralPath $copiedLog -Pattern 'Build\D*(\d{5,})' `
                         -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($buildLine -and $buildLine.Matches.Count) {
            $build = $buildLine.Matches[0].Groups[1].Value
        }
        $serverIps = Select-String -LiteralPath $copiedLog `
                        -Pattern '\b(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}\b' -ErrorAction SilentlyContinue |
                     ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } |
                     Sort-Object -Unique
    }

    if (Test-Path $sessionMd) {
        $md = Get-Content -LiteralPath $sessionMd -Raw
        $md = $md -replace '- game build  : \(filled in when the session ends\)', "- game build  : $build"
        $ipText = if ($serverIps.Count) { ($serverIps -join ', ') } else { '(none found in Game.log)' }
        $md = $md -replace '- server IPs  : \(filled in when the session ends\)', "- server IPs  : $ipText"
        $md += "`n- ended       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        Set-Content -LiteralPath $sessionMd -Value $md -Encoding UTF8
    }

    Write-Host ""
    Write-Host "  Raw session filed at:" -ForegroundColor Green
    Write-Host "    $sessionDir" -ForegroundColor Green

    # ----------------------------------------------------------------------
    #  Build the shareable bundle
    # ----------------------------------------------------------------------
    if ($NoSanitize) {
        Write-Warn2 "-NoSanitize set: shareable bundle not built."
        Write-Warn2 "Build it later with:  scripts\sanitize.ps1 -SessionDir `"$sessionDir`""
    } elseif ($Watch) {
        Write-Warn2 "Watch mode: once you've saved the capture in Wireshark, build the"
        Write-Warn2 "bundle with:  scripts\sanitize.ps1 -SessionDir `"$sessionDir`""
    } else {
        Write-Host ""
        Write-Step "Building the privacy-safe bundle to share ..."
        try {
            & "$PSScriptRoot\sanitize.ps1" -SessionDir $sessionDir
        } catch {
            Write-Err2 "Sanitize step failed: $_"
            Write-Warn2 "Your raw capture is safe. Re-run:"
            Write-Warn2 "  scripts\sanitize.ps1 -SessionDir `"$sessionDir`""
        }
    }

    Write-Host ""
    Write-Host "  Edit session.md to record your character + context while it's fresh." -ForegroundColor Yellow
    Write-Host ""
}
