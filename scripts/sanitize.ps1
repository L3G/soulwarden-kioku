<#
.SYNOPSIS
    SoulwardenKioku -- build a privacy-safe, shareable bundle from a capture session.

.DESCRIPTION
    Takes a session folder produced by capture.ps1 and writes
    <session>_soulwardenkioku.zip -- the ONLY file you should ever share.

    The raw packet capture (pcap\) NEVER leaves your machine. Instead the
    bundle contains data *derived* from it, with your own machine's
    address removed by construction:

        flows.csv          per-packet timing / size / direction with the
                           server endpoint; your own address is not written
        endpoints.txt      summary of the server IPs/ports you talked to
        dtls-handshake.txt the DTLS handshake (cipher, server cert, SNI)
        Game.log           your game log, scrubbed of your Steam auth
                           ticket, persona/account id and Windows username
        session.md         metadata you can edit
        notes.md           your in-game event markers
        submission.md      summary + a report of what was redacted

    For an encrypted game protocol that is everything a researcher can use
    a live capture for -- the raw pcap only adds opaque ciphertext.

    See PRIVACY.md for the full account of what is and is not shared.

.PARAMETER SessionDir
    The session folder to process (contains pcap\, Game.log, ...).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionDir
)

. "$PSScriptRoot\lib.ps1"

if (-not (Test-Path $SessionDir)) {
    Write-Err2 "Session folder not found: $SessionDir"
    return
}
$SessionDir = (Resolve-Path $SessionDir).Path
$sessionName = Split-Path $SessionDir -Leaf

$wsDir = Find-WiresharkDir
if (-not $wsDir) {
    Write-Err2 "Wireshark / tshark not found. Run Setup.cmd first."
    return
}
$Tshark   = Join-Path $wsDir 'tshark.exe'
$Mergecap = Join-Path $wsDir 'mergecap.exe'
$Capinfos = Join-Path $wsDir 'capinfos.exe'

Write-Banner "SoulwardenKioku -- building shareable bundle"
Write-Host "  Session: $sessionName"
Write-Host ""

$outDir = Join-Path $SessionDir 'sanitized'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$redReport = [System.Collections.Generic.List[string]]::new()

# --------------------------------------------------------------------------
#  Host address set -- this machine's own IPs. Any address in here is never
#  written into the bundle; packets are recorded by direction + server peer.
# --------------------------------------------------------------------------
$clientIPs = [System.Collections.Generic.HashSet[string]]::new(
                 [System.StringComparer]::OrdinalIgnoreCase)
try {
    Get-NetIPAddress -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$clientIPs.Add(($_.IPAddress -replace '%.*$','')) }
} catch { }

# A "host" address is one of THIS machine's own IPs. By construction a host
# address is never written into the bundle.
function Test-IsHost($ip) {
    if (-not $ip) { return $false }
    return $clientIPs.Contains($ip)
}
# Multicast / broadcast -- LAN noise, not a game server; dropped from output.
function Test-Multicast($ip) {
    if (-not $ip) { return $false }
    return ($ip -eq '255.255.255.255' -or
            $ip -match '^(22[4-9]|23[0-9])\.' -or
            $ip -match '^(?i)ff[0-9a-f][0-9a-f]:')
}

# --------------------------------------------------------------------------
#  Merge the ring-buffer pcap files into one working file.
# --------------------------------------------------------------------------
$pcaps = @(Get-ChildItem (Join-Path $SessionDir 'pcap') -Filter '*.pcapng' `
              -ErrorAction SilentlyContinue | Sort-Object Name)
$merged   = $null
$haveCap  = $false
if ($pcaps.Count -gt 0) {
    $merged = Join-Path $env:TEMP ("soulwardenkioku_merged_{0}.pcapng" -f ([guid]::NewGuid().ToString('N')))
    Write-Step "Merging $($pcaps.Count) capture file(s) ..."
    & $Mergecap -w $merged @($pcaps.FullName) 2>$null
    $haveCap = (Test-Path $merged)
}
if (-not $haveCap) {
    Write-Warn2 "No packet capture found -- bundle will contain the log + notes only."
}

# --------------------------------------------------------------------------
#  flows.csv  -- per-packet UDP timing / size / direction (client masked)
# --------------------------------------------------------------------------
$pktTotal = 0; $upPkts = 0; $downPkts = 0; $skipped = 0
$peerAgg  = @{}   # "ip|port" -> aggregate stats

if ($haveCap) {
    Write-Step "Extracting per-packet flows ..."
    $rows = & $Tshark -r $merged -Y 'udp' -T fields -E separator='|' `
                -e frame.time_relative -e frame.len `
                -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst `
                -e udp.srcport -e udp.dstport -e udp.length 2>$null

    $csv = [System.Collections.Generic.List[string]]::new()
    $csv.Add('time_relative,direction,frame_bytes,udp_payload_bytes,peer_ip,peer_port')
    foreach ($line in $rows) {
        if (-not $line) { continue }
        $p = $line.Split('|')
        if ($p.Count -lt 9) { continue }
        $t = $p[0]; $flen = $p[1]
        $src = if ($p[2]) { $p[2] } else { $p[4] }
        $dst = if ($p[3]) { $p[3] } else { $p[5] }
        $sport = $p[6]; $dport = $p[7]; $ulen = $p[8]

        $srcHost = Test-IsHost $src
        $dstHost = Test-IsHost $dst
        if ($srcHost -and -not $dstHost) {
            $dir = 'up'; $peer = $dst; $peerPort = $dport
        } elseif ($dstHost -and -not $srcHost) {
            $dir = 'down'; $peer = $src; $peerPort = $sport
        } else {
            # Both ends are this machine, or neither is -- local / non-game
            # traffic. Excluded so no address of yours is ever written.
            $skipped++; continue
        }
        # A multicast/broadcast or host 'peer' is not a game server -- drop it.
        if ((Test-Multicast $peer) -or (Test-IsHost $peer)) { $skipped++; continue }

        $csv.Add(('{0},{1},{2},{3},{4},{5}' -f $t,$dir,$flen,$ulen,$peer,$peerPort))

        $pktTotal++
        if ($dir -eq 'up') { $upPkts++ } else { $downPkts++ }
        $k = "$peer|$peerPort"
        if (-not $peerAgg.ContainsKey($k)) {
            $peerAgg[$k] = [pscustomobject]@{ Peer=$peer; Port=$peerPort
                Packets=0; Up=0; Down=0; Bytes=[long]0 }
        }
        $a = $peerAgg[$k]
        $a.Packets++
        if ($dir -eq 'up') { $a.Up++ } else { $a.Down++ }
        [long]$b = 0; [void][long]::TryParse($flen, [ref]$b); $a.Bytes += $b
    }
    Set-Content -LiteralPath (Join-Path $outDir 'flows.csv') -Value $csv -Encoding UTF8
    Write-Ok "flows.csv -- $pktTotal server packet(s) ($skipped local/multicast excluded)."
    $redReport.Add("flows.csv: $pktTotal server UDP packets; $skipped local/multicast packets excluded; this machine's address is never written.")

    # endpoints.txt -- aggregated from flows.csv, so no client address appears.
    $epLines = [System.Collections.Generic.List[string]]::new()
    $epLines.Add('# Server endpoints contacted this session')
    $epLines.Add('# peer_ip:port   packets   up/down   bytes')
    $epLines.Add('')
    foreach ($a in ($peerAgg.Values | Sort-Object -Property Bytes -Descending)) {
        $epLines.Add(('{0}:{1}   {2} pkts   {3}/{4}   {5} bytes' -f `
            $a.Peer,$a.Port,$a.Packets,$a.Up,$a.Down,$a.Bytes))
    }
    Set-Content -LiteralPath (Join-Path $outDir 'endpoints.txt') -Value $epLines -Encoding UTF8
    Write-Ok "endpoints.txt -- $($peerAgg.Count) server endpoint(s)."

    # dtls-handshake.txt -- handshake fields only (server cert / cipher / SNI).
    Write-Step "Extracting the DTLS handshake ..."
    $hs = & $Tshark -r $merged -Y 'dtls.handshake' -T fields -E separator='|' -E header=y `
              -e frame.number -e frame.time_relative `
              -e dtls.handshake.type -e dtls.handshake.version `
              -e dtls.handshake.ciphersuite -e dtls.handshake.extensions_server_name `
              -e x509sat.printableString -e x509ce.dNSName 2>$null
    $hsOut = [System.Collections.Generic.List[string]]::new()
    $hsOut.Add('# DTLS handshake -- server-side only (cert, cipher, SNI).')
    $hsOut.Add('# Columns: frame | time | hs_type | version | ciphersuite | sni | cert_subject | cert_dns')
    $hsOut.Add('')
    if ($hs) { $hs | ForEach-Object { $hsOut.Add($_) } }
    else     { $hsOut.Add('(no DTLS handshake seen in this capture)') }
    Set-Content -LiteralPath (Join-Path $outDir 'dtls-handshake.txt') -Value $hsOut -Encoding UTF8
    Write-Ok "dtls-handshake.txt written."
}

# --------------------------------------------------------------------------
#  Game.log -- scrub Steam auth ticket, persona/account ids, username.
# --------------------------------------------------------------------------
function Protect-GameLog($srcPath, $dstPath) {
    $text = Get-Content -LiteralPath $srcPath -Raw
    $hits = [ordered]@{}
    function Sub([string]$t, [string]$pat, [string]$rep, [string]$name) {
        $m = [regex]::Matches($t, $pat)
        if ($m.Count -gt 0) { $script:hitCount += $m.Count
                              $script:hitNames += "$name x$($m.Count)" }
        return [regex]::Replace($t, $pat, $rep)
    }
    $script:hitCount = 0
    $script:hitNames = @()

    # Steam auth session ticket -- the long hex blob after 'ticket: steam|'.
    $text = Sub $text '(?i)(ticket:\s*steam\|)[0-9a-f]+' '${1}<REDACTED-STEAM-TICKET>' 'steam-ticket'
    # Any other 'session ticket'-style field followed by a long hex run.
    $text = Sub $text '(?i)(session\s*ticket[^\r\n]{0,40}?[:=]\s*)[0-9a-f]{32,}' '${1}<REDACTED>' 'session-ticket'
    # Amazon persona / account / user ids: amzn1.<type>.<id>
    $text = Sub $text 'amzn1\.[A-Za-z0-9.]+\.[0-9a-fA-F][0-9a-fA-F\-]{7,}' 'amzn1.<REDACTED-ID>' 'amzn1-id'
    # Steam ID 64 (17-digit, starts 7656119).
    $text = Sub $text '\b7656119\d{10}\b' '<REDACTED-STEAMID>' 'steamid64'
    # Windows username inside a filesystem path.
    $text = Sub $text '(?i)([A-Za-z]:[\\/]Users[\\/])[^\\/\r\n]+' '${1}PLAYER' 'username-path'
    # Catch-all: any unbroken 48+ char hex run is a token/key, not log text.
    $text = Sub $text '(?<![0-9a-fA-F])[0-9a-fA-F]{48,}(?![0-9a-fA-F])' '<REDACTED-LONG-HEX>' 'long-hex'
    # The current Windows account name, anywhere it appears literally.
    if ($env:USERNAME -and $env:USERNAME.Length -ge 3) {
        $text = Sub $text ([regex]::Escape($env:USERNAME)) 'PLAYER' 'username'
    }

    Set-Content -LiteralPath $dstPath -Value $text -Encoding UTF8 -NoNewline
    return @{ Count = $script:hitCount; Names = $script:hitNames }
}

$srcLog = Join-Path $SessionDir 'Game.log'
if (Test-Path $srcLog) {
    Write-Step "Scrubbing Game.log ..."
    $r = Protect-GameLog $srcLog (Join-Path $outDir 'Game.log')
    Write-Ok "Game.log scrubbed -- $($r.Count) sensitive value(s) redacted."
    if ($r.Names) { $redReport.Add("Game.log: redacted -- " + ($r.Names -join ', ') + ".") }
    else          { $redReport.Add("Game.log: no known sensitive patterns matched (still review it).") }
} else {
    Write-Warn2 "No Game.log in the session -- skipping."
    $redReport.Add("Game.log: not present in this session.")
}

# --------------------------------------------------------------------------
#  Carry across the player-authored notes.
# --------------------------------------------------------------------------
foreach ($f in @('session.md','notes.md')) {
    $src = Join-Path $SessionDir $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $outDir $f) -Force }
}

# --------------------------------------------------------------------------
#  submission.md -- summary + redaction report.
# --------------------------------------------------------------------------
$capSummary = '(no capture in this session)'
if ($haveCap) {
    $ci = & $Capinfos -M -c -d -u $merged 2>$null
    $capSummary = ($ci | Where-Object { $_ -match '\S' }) -join "`n"
}
$gen = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
@"
# SoulwardenKioku capture submission -- $sessionName

- generated   : $gen
- packets     : $pktTotal UDP ($upPkts up / $downPkts down)
- endpoints   : $($peerAgg.Count) server endpoint(s)

## Capture summary

``````
$capSummary
``````

## What was redacted

$(($redReport | ForEach-Object { "- $_" }) -join "`n")

## Privacy

The raw packet capture stays on the submitter's machine and is NOT in
this bundle. Everything here is derived data with this machine's own
address removed. See PRIVACY.md in the SoulwardenKioku repo for the full account.

## Please review before sharing

Open Game.log, session.md and notes.md and confirm nothing personal
remains. Redaction is automatic but best-effort -- a quick read is the
last safety check.
"@ | Set-Content -LiteralPath (Join-Path $outDir 'submission.md') -Encoding UTF8

# --------------------------------------------------------------------------
#  Zip it.
# --------------------------------------------------------------------------
$zip = Join-Path $SessionDir ("{0}_soulwardenkioku.zip" -f $sessionName)
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force

if ($merged -and (Test-Path $merged)) { Remove-Item $merged -Force -ErrorAction SilentlyContinue }

Write-Banner 'Bundle ready'
Write-Host "  Share this file:" -ForegroundColor Green
Write-Host "    $zip" -ForegroundColor Green
Write-Host ""
Write-Host "  Before sharing, open the 'sanitized' folder and skim Game.log /" -ForegroundColor Yellow
Write-Host "  session.md / notes.md -- a quick read is the final privacy check." -ForegroundColor Yellow
Write-Host "  Then drop the .zip in the community Discord (see CONTRIBUTING.md)." -ForegroundColor Yellow
Write-Host ""
