<#
Start the receive-only JS8Call + CommStat station.

  websdr-js8-start [-NoRoute] [-NoCommStat]

What it does, in order:
  1. Refuses to run unless the JS8Call profile is genuinely receive-only
     (no rig control, no PTT, spotting off) - see "receive-only guard" below.
  2. Checks the virtual audio cable is there: your browser plays the WebSDR into
     one end, and JS8Call listens to the other.
  3. Starts JS8Call (its own profile, so it never touches a normal JS8Call
     setup), waits for its API port, then starts CommStat.
  4. Helps you send the browser's audio into the cable, and checks that it worked.

JS8Call and CommStat are detached from the window that ran this: closing that
window does NOT stop them. Use websdr-js8-stop.
#>
param([switch]$NoRoute, [switch]$NoCommStat, [switch]$Pause, [switch]$Help)
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
$global:WEBSDR_PAUSE = [bool]$Pause
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig

$js8 = Find-Program 'js8call' $c.JS8CALL_EXE
if (-not $js8) { Fail "JS8Call isn't installed. Run install.cmd first (or: winget install JS8Call-improved.JS8Call-improved)." }
if (-not (Test-Path -LiteralPath $c.JS8_INI)) { Fail "JS8Call profile not found: $($c.JS8_INI) - run install.cmd first." }

# ------------------------------------------------------ receive-only guard
# A receive-only station must not be able to key a radio. The profile is written that
# way by the installer; this re-checks it every start in case it was changed later
# inside JS8Call (Settings > Radio), and refuses to start rather than run in a state
# that could transmit.
function Stop-Guard([string]$Why) {
    Fail "receive-only guard: $Why
  This station is meant to be receive-only, so it will not start like this.
  Fix it in $($c.JS8_INI) (or delete that file and re-run install.cmd for a fresh profile)."
}
$ini = $c.JS8_INI
if ((Get-IniValue $ini 'Rig') -ne 'None') { Stop-Guard "the JS8Call profile has Rig='$(Get-IniValue $ini 'Rig')' (must be None)." }
if (Get-IniValue $ini 'CATSerialPort')    { Stop-Guard 'a CAT serial port is configured.' }
if (Get-IniValue $ini 'CATNetworkPort')   { Stop-Guard 'a CAT network port (rigctld) is configured.' }
if (Get-IniValue $ini 'CATUSBPort')       { Stop-Guard 'a CAT USB port is configured.' }
if (Get-IniValue $ini 'PTTport')          { Stop-Guard 'a PTT port is configured.' }
# JS8Call 3.x can run an external program on every transmit (Settings > Radio > PTT command).
if (Get-IniValue $ini 'PTTCommand')       { Stop-Guard "a PTT command is configured ('$(Get-IniValue $ini 'PTTCommand')')." }
# Spotting must be OFF (and explicitly so - JS8Call turns it on when the setting is missing):
# this station hears a REMOTE receiver, so anything it reported to PSKReporter or APRS-IS
# would be attributed to YOUR callsign and grid.
if ((Get-IniValue $ini 'PSKReporter') -ne 'false') { Stop-Guard "PSKReporter spotting isn't switched off (PSKReporter='$(Get-IniValue $ini 'PSKReporter')'). Stations heard via a remote receiver must not be reported under your callsign and grid." }
if ((Get-IniValue $ini 'SpotToAPRS') -ne 'false')  { Stop-Guard "APRS spotting isn't switched off (SpotToAPRS='$(Get-IniValue $ini 'SpotToAPRS')'). Stations heard via a remote receiver must not be reported under your callsign and grid." }
if ((Get-IniValue $ini 'APRSISRelay') -eq 'true')  { Stop-Guard 'APRS-IS relaying is switched on (APRSISRelay=true). Traffic heard via a remote receiver must not be relayed under your callsign.' }

# ------------------------------------------------------- virtual audio cable
Write-Step 'Virtual audio cable'
$play = Find-AudioDevice $c.JS8_PLAY_DEVICE 'Render'
$rec  = Find-AudioDevice $c.JS8_REC_DEVICE 'Capture'
if (-not $play -or -not $rec) {
    Fail "the virtual audio cable isn't there (looking for '$($c.JS8_PLAY_DEVICE)' and '$($c.JS8_REC_DEVICE)').
  Install VB-CABLE (https://vb-audio.com/Cable/) and restart Windows, or set JS8_PLAY_DEVICE /
  JS8_REC_DEVICE in $($c.CONFIG_DIR)\config to the cable you have."
}
$txName = Get-IniValue $ini 'SoundOutName'
$tx = Find-AudioDevice $c.JS8_TX_DEVICE 'Render'
if (-not (Test-SameDeviceName $txName $(if ($tx) { $tx.Name } else { $c.JS8_TX_DEVICE }))) {
    Write-Warn "JS8Call's audio OUTPUT is '$txName', not '$($c.JS8_TX_DEVICE)'; a transmit attempt could make sound on your speakers (it still cannot key a radio)."
}
if ((Get-IniValue $ini 'SoundInName') -and -not (Test-SameDeviceName (Get-IniValue $ini 'SoundInName') $rec.Name)) {
    Write-Warn "JS8Call's audio INPUT is '$(Get-IniValue $ini 'SoundInName')', not the cable ('$($rec.Name)'). Pick the cable in JS8Call's File > Settings > Audio, or it won't hear the WebSDR."
}
$def = Get-DefaultAudioDevice 'Render'
if ($def -and $def.Id -eq $play.Id) { Write-Warn "'$($play.Name)' is Windows' DEFAULT playback device, so every program's sound goes into JS8Call. Set your speakers as the default in Settings > System > Sound." }
if ((@(Get-FldigiProcess $c).Count -gt 0) -and ($c.FL_PLAY_DEVICE -eq $c.JS8_PLAY_DEVICE)) {
    Write-Warn "the FLDIGI station is running on the same cable, so both decoders hear the same audio. Stop it (websdr-fldigi-stop), or give it a second cable."
}
Write-Info "Ready: browser -> '$($play.Name)' -> JS8Call records '$($rec.Name)'."

# ---------------------------------------------------------------- JS8Call
Write-Step "JS8Call (profile: $($c.PROFILE))"
New-Item -ItemType Directory -Force -Path $c.DATA_DIR | Out-Null
if (@(Get-Js8Process $c).Count -gt 0) {
    Write-Info 'Already running.'
} else {
    # A GUI program started this way has no console of its own, so closing this window
    # can't close it.
    [void](Start-Detached $js8 @('-r', $c.PROFILE) (Split-Path -Parent $js8) '')
    Write-Info "Started. Waiting for its API port ($($c.TCP_PORT))..."
    if (Wait-Port $c.TCP_PORT 40) { Write-Info 'JS8Call is up.' }
    else { Write-Warn "JS8Call's API port $($c.TCP_PORT) didn't open in 40 s. Is JS8Call showing a dialog? (File > Settings > Reporting > 'Enable TCP Server API' must stay on.)" }
}

# --------------------------------------------------------------- CommStat
if (-not $NoCommStat) {
    Write-Step 'CommStat'
    $pyw = Join-Path (Split-Path -Parent $c.PYTHON) 'pythonw.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $c.COMMSTAT_DIR 'commstat.py'))) {
        Write-Warn "CommStat not found at $($c.COMMSTAT_DIR) - skipping (run install.cmd, or use -NoCommStat)."
    } elseif (-not (Test-Path -LiteralPath $pyw)) {
        Write-Warn "CommStat's Python ($pyw) is missing - skipping (run install.cmd again)."
    } elseif (@(Get-CommStatProcess $c).Count -gt 0) {
        Write-Info 'Already running.'
    } else {
        # CommStat's launcher (commstat.py) applies a pending self-update, creates the database
        # if needed, then runs the app (little_gucci.py). Under pythonw that launcher exits at
        # once with no output, so its first two steps run here (console Python, waited for),
        # and the app itself is started with pythonw: no console window, so closing this
        # window can't close it. CommStat connects to JS8Call once, at startup - which is why
        # JS8Call's port must already be open (waited for above). It runs from its own folder
        # (its database path is relative).
        $prep = 'import commstat; commstat.UPDATE_FOLDER.mkdir(parents=True, exist_ok=True); commstat.apply_update(); commstat.setup_database()'
        if ((Invoke-Native $c.PYTHON @('-c', $prep) $c.COMMSTAT_DIR) -ne 0) { Write-Warn "CommStat's update/database check reported a problem (see above); starting it anyway." }
        $log = Join-Path $c.DATA_DIR 'commstat.log'
        # CommStat's window needs about 1360x768; on a smaller screen (or high Windows scaling)
        # COMMSTAT_SCALE draws it smaller. Only CommStat gets the variable.
        if ($c.COMMSTAT_SCALE -match '^(0?\.\d+|[0-3](\.\d+)?)$') { $env:QT_SCALE_FACTOR = $c.COMMSTAT_SCALE }
        [void](Start-Detached $pyw @((Join-Path $c.COMMSTAT_DIR 'little_gucci.py')) $c.COMMSTAT_DIR $log)
        Remove-Item Env:\QT_SCALE_FACTOR -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        if (@(Get-CommStatProcess $c).Count -gt 0) { Write-Info "Started (log: $log)." }
        else { Write-Warn "CommStat exited straight away - see $log and $log.err." }
    }
}

# ----------------------------------------------------------------- routing
if ($NoRoute) { Write-Info ''; Write-Info 'Skipping audio routing (-NoRoute). Stop everything with: websdr-js8-stop'; Exit-Script 0 }
[void](Invoke-BrowserRouting $play 'JS8Call' 'Tune it to a JS8 frequency in USB mode (for example 7.078 MHz).' 'websdr-js8-start' 'websdr-js8-stop')
Exit-Script 0
