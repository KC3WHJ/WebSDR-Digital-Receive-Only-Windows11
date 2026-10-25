<#
Start the receive-only FLDIGI + FLMSG + FLAMP station.

  websdr-fldigi-start [-NoRoute]

What it does, in order:
  1. On first run, creates FLDIGI settings of its own (a copy of your fldigi.files if
     you have one, so your macros and frequency list carry over) and FLMSG/FLAMP
     settings of their own. A normal FLDIGI setup is never touched.
  2. Applies the receive-only settings - no rig control, no PTT of any kind, no
     spotting - and refuses to start if they can't be confirmed (receive-only guard).
  3. Checks the virtual audio cable is there: your browser plays the WebSDR into one
     end, and FLDIGI listens to the other.
  4. Starts FLDIGI on its own ports, then FLMSG and FLAMP, which talk only to this FLDIGI.
  5. Helps you send the browser's audio into the cable, and checks that it worked.

Everything is detached from the window that ran this: closing that window does NOT
stop it. Use websdr-fldigi-stop.
#>
param([switch]$NoRoute, [switch]$Pause, [switch]$Help)
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Fldigi.ps1')
$global:WEBSDR_PAUSE = [bool]$Pause
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig

$fldigi = Find-Program 'fldigi' $c.FLDIGI_EXE
$flmsg  = Find-Program 'flmsg' $c.FLMSG_EXE
$flamp  = Find-Program 'flamp' $c.FLAMP_EXE
if (-not $fldigi) { Fail "FLDIGI isn't installed. Run install.cmd first (or: winget install w1hkj.fldigi w1hkj.flmsg w1hkj.flamp)." }

$FL_DATA = Join-Path $c.DATA_DIR 'fldigi'
New-Item -ItemType Directory -Force -Path $FL_DATA | Out-Null

# ------------------------------------------------------- virtual audio cable
$play = Find-AudioDevice $c.FL_PLAY_DEVICE 'Render'
$rec  = Find-AudioDevice $c.FL_REC_DEVICE 'Capture'
if (-not $play -or -not $rec) {
    Fail "the virtual audio cable isn't there (looking for '$($c.FL_PLAY_DEVICE)' and '$($c.FL_REC_DEVICE)').
  Install VB-CABLE (https://vb-audio.com/Cable/) and restart Windows, or set FL_PLAY_DEVICE /
  FL_REC_DEVICE in $($c.CONFIG_DIR)\config to the cable you have."
}
$tx = Find-AudioDevice $c.FL_TX_DEVICE 'Render'
$txName = if ($tx) { $tx.Name } else { Write-Warn "transmit device '$($c.FL_TX_DEVICE)' not found - using the cable."; $play.Name }

# Wrappers that FLDIGI runs to open a received message in this station's FLMSG.
$flmsgCmd = Join-Path $FL_DATA 'websdr-flmsg.cmd'
$flampCmd = Join-Path $FL_DATA 'websdr-flamp.cmd'
$nb = ConvertTo-FlPath $c.NBEMS_DIR
if ($flmsg) { Write-TextFile $flmsgCmd "@echo off`r`nstart `"`" `"$flmsg`" --flmsg-dir `"$nb`" %*`r`n" }
if ($flamp) { Write-TextFile $flampCmd "@echo off`r`nstart `"`" `"$flamp`" --config-dir `"$nb`" --xmlrpc-server-port $($c.FL_XMLRPC_PORT) --arq-server-port $($c.FL_ARQ_PORT) %*`r`n" }

# ------------------------------------------------------------ settings
Initialize-FldigiSettings $c
if (@(Get-FldigiProcess $c).Count -gt 0) {
    Write-Step 'FLDIGI (WebSDR) is already running - leaving its settings alone'
} else {
    Write-Step 'Applying receive-only settings'
    Set-FldigiReceiveOnly $c $rec.Name $txName $flmsgCmd $flampCmd
    $why = Test-FldigiReceiveOnly $c
    if ($why) {
        Fail "receive-only guard: $why
  This station is meant to be receive-only, so it will not start like this.
  Check $(Join-Path $c.FLDIGI_DIR 'fldigi_def.xml') (or delete $($c.FLDIGI_DIR) to start over)."
    }
    Write-Info "No rig control, no PTT, no spotting. Audio: records '$($rec.Name)', transmit audio into '$txName'."
}
$def = Get-DefaultAudioDevice 'Render'
if ($def -and $def.Id -eq $play.Id) { Write-Warn "'$($play.Name)' is Windows' DEFAULT playback device, so every program's sound goes into FLDIGI. Set your speakers as the default in Settings > System > Sound." }
if ((@(Get-Js8Process $c).Count -gt 0) -and ($c.FL_PLAY_DEVICE -eq $c.JS8_PLAY_DEVICE)) {
    Write-Warn "the JS8Call station is running on the same cable, so both decoders hear the same audio. Stop it (websdr-js8-stop), or give this station a second cable."
}

# ------------------------------------------------------------------ FLDIGI
Write-Step "FLDIGI (settings: $($c.FLDIGI_DIR))"
if (@(Get-FldigiProcess $c).Count -gt 0) {
    Write-Info 'Already running.'
} else {
    $fa = @('--config-dir', (ConvertTo-FlPath $c.FLDIGI_DIR), '--flmsg-dir', $nb,
            '--xmlrpc-server-port', $c.FL_XMLRPC_PORT, '--arq-server-port', $c.FL_ARQ_PORT,
            '--kiss-server-port-io', $c.FL_KISS_IO_PORT, '--kiss-server-port-o', $c.FL_KISS_OUT_PORT)
    [void](Start-Detached $fldigi $fa (Split-Path -Parent $fldigi) '')
    Write-Info "Started. Waiting for its XML-RPC port ($($c.FL_XMLRPC_PORT))..."
    if (Wait-Port $c.FL_XMLRPC_PORT 40) { Write-Info 'FLDIGI is up.' }
    else { Write-Warn "FLDIGI's XML-RPC port $($c.FL_XMLRPC_PORT) didn't open in 40 s - FLMSG and FLAMP may not connect. Is FLDIGI showing a dialog?" }
}

# ---------------------------------------------------------- FLMSG and FLAMP
Write-Step 'FLMSG and FLAMP'
if (-not $flmsg) { Write-Warn "FLMSG isn't installed (winget install w1hkj.flmsg) - skipping." }
elseif (@(Get-FlmsgProcess $c).Count -gt 0) { Write-Info 'FLMSG already running.' }
else { [void](Start-Detached $flmsg @('--flmsg-dir', $nb) (Split-Path -Parent $flmsg) ''); Write-Info 'FLMSG started.' }
if (-not $flamp) { Write-Warn "FLAMP isn't installed (winget install w1hkj.flamp) - skipping." }
elseif (@(Get-FlampProcess $c).Count -gt 0) { Write-Info 'FLAMP already running.' }
else {
    # --config-dir takes the NBEMS folder; FLAMP uses its FLAMP\ subfolder. (FLAMP's --help
    # spells it "--confg-dir", which FLAMP itself doesn't accept.)
    [void](Start-Detached $flamp @('--config-dir', $nb, '--xmlrpc-server-port', $c.FL_XMLRPC_PORT, '--arq-server-port', $c.FL_ARQ_PORT) (Split-Path -Parent $flamp) '')
    Write-Info 'FLAMP started.'
}

# ----------------------------------------------------------------- routing
if ($NoRoute) { Write-Info ''; Write-Info 'Skipping audio routing (-NoRoute). Stop with: websdr-fldigi-stop'; Exit-Script 0 }
[void](Invoke-BrowserRouting $play 'FLDIGI' "Tune it in USB to the dial frequency you'd use on a radio (e.g. 7.110 MHz)." 'websdr-fldigi-start' 'websdr-fldigi-stop')
Exit-Script 0
