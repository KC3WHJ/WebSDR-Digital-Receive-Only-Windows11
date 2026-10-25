# FLDIGI / FLMSG / FLAMP settings for the receive-only station. Dot-sourced by
# websdr-fldigi-start.ps1 (and the tests), after lib\Common.ps1.

# A normal (radio) setup's folders: only ever read, to copy from on first start.
$NORMAL_FLDIGI_DIR = if ($env:WEBSDR_JS8_NORMAL_FLDIGI_DIR) { $env:WEBSDR_JS8_NORMAL_FLDIGI_DIR } else { Join-Path $env:USERPROFILE 'fldigi.files' }
$NORMAL_NBEMS_DIR  = if ($env:WEBSDR_JS8_NORMAL_NBEMS_DIR)  { $env:WEBSDR_JS8_NORMAL_NBEMS_DIR }  else { Join-Path $env:USERPROFILE 'NBEMS.files' }

# ---------------------------------------------------------- fldigi_def.xml
# One <KEY>value</KEY> per line inside <FLDIGI_DEFS>; FLDIGI reads them in any order.
function ConvertTo-XmlText([string]$v) { $v.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
function ConvertFrom-XmlText([string]$v) { $v.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&amp;', '&') }

# Set one setting in the file's text, adding it if it isn't there yet.
function Set-XmlSetting([ref]$Text, [string]$Key, [string]$Value) {
    $v = (ConvertTo-XmlText $Value).Replace('$', '$$')
    $re = "(?m)^<$Key>.*</$Key>\r?$"
    if ([regex]::IsMatch($Text.Value, $re)) {
        $Text.Value = [regex]::Replace($Text.Value, $re, "<$Key>$v</$Key>")
    } else {
        $Text.Value = [regex]::Replace($Text.Value, '(?m)^</FLDIGI_DEFS>', "<$Key>$v</$Key>`n</FLDIGI_DEFS>")
    }
}
function Get-XmlSetting([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, "(?m)^<$Key>(.*)</$Key>\r?$")
    if ($m.Success) { return (ConvertFrom-XmlText $m.Groups[1].Value) } else { return $null }
}

# Replace every occurrence of a folder path (either slash style, any case) with another.
function Convert-FolderPaths([string]$Text, [string]$From, [string]$To) {
    foreach ($pair in @(@(($From.TrimEnd('\') + '\'), ($To.TrimEnd('\') + '\')), @((ConvertTo-FlPath $From), (ConvertTo-FlPath $To)))) {
        $Text = [regex]::Replace($Text, [regex]::Escape($pair[0]), $pair[1].Replace('$', '$$'), 'IgnoreCase')
    }
    return $Text
}

# ------------------------------------------------- FLMSG / FLAMP preferences
# FLTK preference files: "key:value" lines. Created if missing.
function Set-PrefSetting([string]$File, [string]$App, [string]$Key, [string]$Value) {
    if (-not (Test-Path -LiteralPath $File)) {
        Write-TextFile $File "; FLTK preferences file format 1.0`n; vendor: w1hkj.com`n; application: $App`n`n[.]`n`n"
    }
    $t = [IO.File]::ReadAllText($File)
    $re = "(?m)^$([regex]::Escape($Key)):.*$"
    if ([regex]::IsMatch($t, $re)) { $t = [regex]::Replace($t, $re, "${Key}:$($Value.Replace('$', '$$'))") }
    else { if ($t -and -not $t.EndsWith("`n")) { $t += "`n" }; $t += "${Key}:$Value`n" }
    Write-TextFile $File $t
}
function Get-PrefSetting([string]$File, [string]$Key) {
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    $m = [regex]::Match([IO.File]::ReadAllText($File), "(?m)^$([regex]::Escape($Key)):(.*?)\r?$")
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

# ------------------------------------------------------------ first-run setup
# Settings of the station's own: a copy of the normal FLDIGI setup if there is one (so
# macros, the frequency list and modem settings carry over), else fresh ones.
function Initialize-FldigiSettings($c) {
    $xml = Join-Path $c.FLDIGI_DIR 'fldigi_def.xml'
    if (-not (Test-Path -LiteralPath $xml)) {
        Write-Step "Creating FLDIGI settings for the WebSDR station ($($c.FLDIGI_DIR))"
        if (Test-Path -LiteralPath (Join-Path $NORMAL_FLDIGI_DIR 'fldigi_def.xml')) {
            Copy-Item -Recurse -LiteralPath $NORMAL_FLDIGI_DIR -Destination $c.FLDIGI_DIR
            foreach ($junk in 'temp', 'debug') {
                $d = Join-Path $c.FLDIGI_DIR $junk
                if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d | Remove-Item -Recurse -Force }
            }
            Remove-Item -Force -LiteralPath (Join-Path $c.FLDIGI_DIR 'fldigi_def.xml-old') -ErrorAction SilentlyContinue
            Write-Info "Copied from $NORMAL_FLDIGI_DIR (your normal FLDIGI settings are left as they are)."
        } else {
            # Fresh settings follow a net that changes modes (e.g. Contestia for the net,
            # MFSK-32 for FLMSG/FLAMP traffic): receive RSID on, still listening after each
            # RSID it hears, and switching the modem rather than only notifying. This only
            # listens; transmit RSID stays off (below). A copied setup keeps its own choice.
            Write-TextFile $xml "<FLDIGI_DEFS>`n<RECEIVERSID>1</RECEIVERSID>`n<RSIDAUTODISABLE>0</RSIDAUTODISABLE>`n<RSIDNOTIFYONLY>0</RSIDNOTIFYONLY>`n</FLDIGI_DEFS>`n"
            Write-Info 'Created fresh settings (receive RSID on).'
        }
        $t = [IO.File]::ReadAllText($xml)
        if ($c.CALLSIGN) { Set-XmlSetting ([ref]$t) 'MYCALL' $c.CALLSIGN }
        if ($c.GRID)     { Set-XmlSetting ([ref]$t) 'MYLOC' $c.GRID }
        Write-TextFile $xml $t
    }
    $flmsgPrefs = Join-Path $c.NBEMS_DIR 'FLMSG.prefs'
    if (-not (Test-Path -LiteralPath $flmsgPrefs)) {
        Write-Step "Creating FLMSG/FLAMP settings for the WebSDR station ($($c.NBEMS_DIR))"
        New-Item -ItemType Directory -Force -Path (Join-Path $c.NBEMS_DIR 'FLAMP') | Out-Null
        # Settings and custom forms carry over; received messages don't.
        $src = Join-Path $NORMAL_NBEMS_DIR 'FLMSG.prefs';        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $c.NBEMS_DIR }
        $src = Join-Path $NORMAL_NBEMS_DIR 'CUSTOM';             if (Test-Path -LiteralPath $src) { Copy-Item -Recurse -LiteralPath $src -Destination $c.NBEMS_DIR }
        $src = Join-Path $NORMAL_NBEMS_DIR 'FLAMP\FLAMP.prefs';  if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $c.NBEMS_DIR 'FLAMP') }
        if ($c.CALLSIGN) {
            Set-PrefSetting $flmsgPrefs 'FLMSG' 'mycall' $c.CALLSIGN
            Set-PrefSetting (Join-Path $c.NBEMS_DIR 'FLAMP\FLAMP.prefs') 'FLAMP' 'mycall' $c.CALLSIGN
        }
    }
}

# ------------------------------------------------------ receive-only settings
$FL_ZERO_KEYS = @(
    # No rig control of any kind (Hamlib, RigCAT, flrig/XML-RPC).
    'CHKUSEHAMLIBIS', 'CHKUSERIGCATIS', 'CHKUSEXMLRPCIS', 'FLRIG_AUTO_ENABLE', 'FLRIG_KEYS_MODEM', 'CLIENT_TO_FLRIG',
    # No PTT or keying line of any kind.
    'HAMLIBCMDPTT', 'RIGCATCMDPTT', 'TTYPTT', 'RTSPTT', 'DTRPTT', 'RTSPLUS', 'DTRPLUS', 'USEUHROUTERPTT', 'USEPPORTPTT',
    'USE_GPIO_PTT', 'ENABLE_GPIO', 'USE_GPIO_CW', 'ENABLE_GPIO_CW', 'PTTRIGHTCHANNEL', 'RIGCATRTSPTT', 'RIGCATDTRPTT',
    'CWKEYLINE', 'PTTKEYLINE', 'FSK_ON_DTR',
    # No spotting or uploads: this station hears a REMOTE receiver, so anything it reported
    # would be attributed to YOUR callsign and location.
    'USEPSKREP', 'PSKREP_AUTOSTART', 'PSKREPAUTO', 'PSKREPLOG', 'DXC_AUTO_CONNECT', 'SPOT_WHEN_LOGGED', 'EQSL_WHEN_LOGGED', 'SUBMIT_LOTW',
    # Nothing to key up for (and no RSID sent before or after a transmission).
    'TRANSMITRSID', 'RSIDPOST', 'PRETONE',
    # FLDIGI's own autostart is off: the launcher starts FLMSG and FLAMP itself, with this
    # station's folder and ports, and nothing else (a copied setup might autostart flrig).
    'FLAMP_AUTO_ENABLE', 'PROG1_AUTO_ENABLE', 'PROG2_AUTO_ENABLE', 'PROG3_AUTO_ENABLE'
)
$FL_GUARD_KEYS = @(
    'CHKUSEHAMLIBIS', 'CHKUSERIGCATIS', 'CHKUSEXMLRPCIS', 'HAMLIBCMDPTT', 'RIGCATCMDPTT', 'TTYPTT', 'RTSPTT', 'DTRPTT',
    'USEUHROUTERPTT', 'USEPPORTPTT', 'USE_GPIO_PTT', 'PTTRIGHTCHANNEL', 'CWKEYLINE', 'PTTKEYLINE',
    'USEPSKREP', 'PSKREP_AUTOSTART', 'PSKREPAUTO', 'PSKREPLOG'
)

# FLDIGI rewrites its settings when it exits, so they are (re)applied while it's stopped, on
# every start - which also undoes anything changed later in its Configure dialogs.
# $RecName / $TxName: the audio devices FLDIGI records from / plays into.
# $FlmsgCmd / $FlampCmd: the wrappers that start FLMSG / FLAMP for this station.
function Set-FldigiReceiveOnly($c, [string]$RecName, [string]$TxName, [string]$FlmsgCmd, [string]$FlampCmd) {
    $xml = Join-Path $c.FLDIGI_DIR 'fldigi_def.xml'
    $t = [IO.File]::ReadAllText($xml)
    # Audio through PortAudio, by device name (index -1 = look it up by name).
    Set-XmlSetting ([ref]$t) 'AUDIOIO' '1'
    Set-XmlSetting ([ref]$t) 'PORTINDEVICE' $RecName;  Set-XmlSetting ([ref]$t) 'PORTININDEX' '-1'
    Set-XmlSetting ([ref]$t) 'PORTOUTDEVICE' $TxName;  Set-XmlSetting ([ref]$t) 'PORTOUTINDEX' '-1'
    foreach ($k in $FL_ZERO_KEYS) { Set-XmlSetting ([ref]$t) $k '0' }
    foreach ($k in 'CMEDIA_DEVICE', 'NANOSERIALPORTNAME', 'NAVFSKPORT', 'NAVCONFIGPORT') { Set-XmlSetting ([ref]$t) $k 'NONE' }
    # Its own ports.
    Set-XmlSetting ([ref]$t) 'XMLRPC_PORT' $c.FL_XMLRPC_PORT;     Set-XmlSetting ([ref]$t) 'ARQ_PORT' $c.FL_ARQ_PORT
    Set-XmlSetting ([ref]$t) 'KISS_IO_PORT' $c.FL_KISS_IO_PORT;   Set-XmlSetting ([ref]$t) 'KISS_OUT_PORT' $c.FL_KISS_OUT_PORT
    # A received FLMSG message opens in this station's FLMSG.
    Set-XmlSetting ([ref]$t) 'AUTO_FLAMP_PATHNAME' $FlampCmd
    Set-XmlSetting ([ref]$t) 'AUTO_PROG1_PATHNAME' $FlmsgCmd
    Set-XmlSetting ([ref]$t) 'FLMSG_PATHNAME' $FlmsgCmd
    # A copied setup keeps absolute paths into the normal folder (e.g. the macro file); point them here.
    $t = Convert-FolderPaths $t $NORMAL_FLDIGI_DIR $c.FLDIGI_DIR
    Write-TextFile $xml $t
    $prefs = Join-Path $c.FLDIGI_DIR 'fldigi.prefs'
    if (Test-Path -LiteralPath $prefs) { Write-TextFile $prefs (Convert-FolderPaths ([IO.File]::ReadAllText($prefs)) $NORMAL_FLDIGI_DIR $c.FLDIGI_DIR) }

    # FLMSG and FLAMP: talk to this FLDIGI, and never transmit on their own.
    Set-PrefSetting (Join-Path $c.NBEMS_DIR 'FLMSG.prefs') 'FLMSG' 'xmlrpc_port' $c.FL_XMLRPC_PORT
    $f = Join-Path $c.NBEMS_DIR 'FLAMP\FLAMP.prefs'
    Set-PrefSetting $f 'FLAMP' 'xmlrpc_port' $c.FL_XMLRPC_PORT
    Set-PrefSetting $f 'FLAMP' 'socket_port' $c.FL_ARQ_PORT
    foreach ($k in 'repeat_forever', 'repeat_at_times', 'use_tx_on_report', 'enable_tx_unproto', 'auto_load_queue', 'use_repeater_interval') {
        Set-PrefSetting $f 'FLAMP' $k '0'
    }
}

# The guard: check the result rather than trusting the edits above. Returns why the
# settings are NOT receive-only, or $null when they are.
function Test-FldigiReceiveOnly($c) {
    $t = [IO.File]::ReadAllText((Join-Path $c.FLDIGI_DIR 'fldigi_def.xml'))
    foreach ($k in $FL_GUARD_KEYS) {
        $v = Get-XmlSetting $t $k
        if ($v -ne '0') { return "$k is '$v' (must be 0)." }
    }
    if ((Get-XmlSetting $t 'AUDIOIO') -ne '1') { return "FLDIGI's audio isn't set to PortAudio, so its output can't be pointed at the cable." }
    return $null
}
