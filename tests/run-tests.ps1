<#
Test suite for WebSDR-Digital-Receive-Only (Windows). No administrator rights, GUI or
internet needed: it uses temporary folders, its own profile name and ports, and a
compiled stand-in for js8call.exe, so it can run beside a live install.

  powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1

Checks that need audio devices use whatever this PC has (any speakers and microphone)
and are skipped when there are none.
#>
$ErrorActionPreference = 'Continue'
$ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $ROOT 'lib\Common.ps1')
. (Join-Path $ROOT 'lib\Fldigi.ps1')

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Assert([bool]$Cond, [string]$Name, [string]$Info = '') {
    if ($Cond) { $script:pass++; Write-Host "  ok    $Name" }
    else { $script:fail++; Write-Host "  FAIL  $Name" -ForegroundColor Red; if ($Info) { Write-Host "        $Info" -ForegroundColor DarkGray } }
}
function Skip([string]$Name, [string]$Why) { $script:skip++; Write-Host "  skip  $Name ($Why)" -ForegroundColor Yellow }
function Section([string]$Name) { Write-Host "`n== $Name" -ForegroundColor White }

# A sandbox: every WEBSDR_JS8_* path points into a fresh temp folder.
$SANDBOX = Join-Path ([IO.Path]::GetTempPath()) ("wsdr-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $SANDBOX | Out-Null
$ENV_KEYS = @()
function Set-TestEnv([hashtable]$Vars) {
    foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable("WEBSDR_JS8_$k", $Vars[$k]); $script:ENV_KEYS += "WEBSDR_JS8_$k" }
}
function Clear-TestEnv { foreach ($k in $script:ENV_KEYS) { [Environment]::SetEnvironmentVariable($k, $null) }; $script:ENV_KEYS = @() }
function Use-Sandbox {
    Clear-TestEnv
    Set-TestEnv @{ CONFIG_DIR = "$SANDBOX\config"; DATA_DIR = "$SANDBOX\data"; JS8_HOME = "$SANDBOX\js8home"; PROFILE = 'WsdrTest'
                   FLDIGI_DIR = "$SANDBOX\fldigi-websdr"; NBEMS_DIR = "$SANDBOX\nbems-websdr"; NORMAL_FLDIGI_DIR = "$SANDBOX\normal-fldigi"
                   NORMAL_NBEMS_DIR = "$SANDBOX\normal-nbems"; COMMSTAT_DIR = "$SANDBOX\CommStat"; TCP_PORT = '24431'
                   MENU_DIR = "$SANDBOX\startmenu\WebSDR Digital Receive-Only"; DESKTOP_DIR = "$SANDBOX\desktop" }
}
# Run a script in a fresh Windows PowerShell; returns @{ Code; Out }.
function Invoke-Script([string]$Rel, [string[]]$Arguments = @()) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ROOT $Rel) @Arguments 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out }
}

try {
# ------------------------------------------------------------------ validation
Section 'Validation'
Assert (Test-Callsign 'W1AW') 'callsign W1AW'
Assert (Test-Callsign 'w1aw/p') 'callsign w1aw/p'
Assert (-not (Test-Callsign 'W1')) 'callsign too short rejected'
Assert (-not (Test-Callsign 'W1AW;rm')) 'callsign with ; rejected'
Assert (Test-Grid 'FN31') 'grid FN31'
Assert (Test-Grid 'fn31pr') 'grid fn31pr'
Assert (-not (Test-Grid 'FZ31')) 'grid FZ31 rejected'
Assert (-not (Test-Grid 'FN31p')) 'grid FN31p rejected'
Assert ((Format-Grid 'fn31PR') -ceq 'FN31pr') 'grid formatted FN31pr'
Assert (Test-State '') 'empty state allowed'
Assert (Test-State 'pa') 'state pa'
Assert (-not (Test-State 'PAX')) 'state PAX rejected'
Assert (Test-Port '2443') 'port 2443'
Assert (-not (Test-Port '80')) 'port 80 rejected'
Assert (-not (Test-Port '70000')) 'port 70000 rejected'
Assert (-not (Test-Port '24a3')) 'port 24a3 rejected'
Assert (Test-ProfileName 'WebSDR_2') 'profile WebSDR_2'
Assert (-not (Test-ProfileName 'Web SDR')) 'profile with a space rejected'
Assert (Test-DeviceName 'CABLE Input (VB-Audio Virtual Cable)') 'device name with spaces and brackets'
Assert (-not (Test-DeviceName 'a"b')) 'device name with a quote rejected'

# ------------------------------------------------------------------ settings
Section 'Settings'
Use-Sandbox
$c = Get-WebSdrConfig
Assert ($c.PROFILE -eq 'WsdrTest') 'environment overrides the default'
Assert ($c.JS8_TX_DEVICE -eq $c.JS8_PLAY_DEVICE) 'blank JS8_TX_DEVICE means the cable'
Assert ($c.JS8_INI -eq "$SANDBOX\js8home\JS8Call - WsdrTest.ini") 'JS8Call profile path'
New-Item -ItemType Directory -Force -Path "$SANDBOX\config" | Out-Null
[IO.File]::WriteAllText("$SANDBOX\config\config", "# comment`r`nCALLSIGN=`"N0CALL`"`r`nGRID=FN31pr`r`nEVIL=1`r`nJS8_REC_DEVICE=Line 1 (Virtual Audio Cable)`r`nnot a setting`r`n")
$c = Get-WebSdrConfig
Assert ($c.CALLSIGN -eq 'N0CALL') 'config file read, quotes stripped'
Assert ($c.JS8_REC_DEVICE -eq 'Line 1 (Virtual Audio Cable)') 'value with spaces and brackets kept whole'
Assert (-not $c.Contains('EVIL')) 'unknown key ignored'
$c.STATE = 'PA'; Save-WebSdrConfig $c
$c2 = Get-WebSdrConfig
Assert ($c2.STATE -eq 'PA' -and $c2.GRID -eq 'FN31pr') 'settings round-trip through the file'
Assert (-not ([IO.File]::ReadAllBytes("$SANDBOX\config\config")[0] -eq 0xEF)) 'config written without a byte-order mark'

# ------------------------------------------------------------------ command lines
Section 'Command-line quoting'
Add-Type -Namespace WsdrTest -Name Argv -MemberDefinition @'
[DllImport("shell32.dll", SetLastError = true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string cmd, out int n);
[DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
public static string[] Split(string cmd) {
    int n; IntPtr a = CommandLineToArgvW(cmd, out n); var r = new string[n];
    for (int i = 0; i < n; i++) r[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(a, i * IntPtr.Size));
    LocalFree(a); return r;
}
'@
$cases = @('plain', '', 'two words', 'C:\Program Files\x\', 'say "hi"', 'C:/Users/me/NBEMS-websdr.files/', 'a\\"b', '\')
$split = [WsdrTest.Argv]::Split('prog.exe ' + (Join-Args $cases))
Assert ($split.Count -eq $cases.Count + 1) 'every argument survives, including an empty one' "got $($split.Count - 1)"
for ($i = 0; $i -lt $cases.Count; $i++) { Assert ($split[$i + 1] -ceq $cases[$i]) "argument round-trips: [$($cases[$i])]" "got [$($split[$i + 1])]" }
Assert ((ConvertTo-FlPath 'C:\Users\me\fldigi-websdr.files\') -eq 'C:/Users/me/fldigi-websdr.files/') 'FLDIGI path form: forward slashes, one trailing slash'

# ------------------------------------------------------------------ JS8Call guard
Section 'JS8Call receive-only guard'
Use-Sandbox
# A stand-in js8call.exe: a windowless program that just waits, so process matching and
# stopping can be tested without JS8Call.
$stubDir = "$SANDBOX\stub"; New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
Add-Type -OutputType WindowsApplication -OutputAssembly "$stubDir\js8call.exe" -TypeDefinition 'public static class P { public static void Main() { System.Threading.Thread.Sleep(60000); } }'
Set-TestEnv @{ JS8CALL_EXE = "$stubDir\js8call.exe" }
$good = [IO.File]::ReadAllText("$ROOT\share\JS8Call-profile.ini.template").Replace('@CALLSIGN@', 'N0CALL').Replace('@GRID@', 'FN31').Replace('@TCP_PORT@', '24431').Replace('@UDP_PORT@', '22381').Replace('@SAVE_DIR@', 'x').Replace('@REC_DEVICE@', 'CABLE Output').Replace('@TX_DEVICE@', 'CABLE Input')
$ini = "$SANDBOX\js8home\JS8Call - WsdrTest.ini"
$r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
Assert ($r.Code -ne 0 -and $r.Out -match 'profile not found') 'refuses without a profile'
$bad = @{ 'Rig=None' = 'Rig=Hamlib'; 'CATSerialPort=' = 'CATSerialPort=COM3'; 'CATNetworkPort=' = 'CATNetworkPort=127.0.0.1:4532'; 'PTTport=' = 'PTTport=COM4'
          'PSKReporter=false' = 'PSKReporter=true'; 'SpotToAPRS=false' = 'SpotToAPRS=true'
          'CATUSBPort=' = 'CATUSBPort=USB1'; 'PTTCommand=' = 'PTTCommand=C:\ptt.exe'; 'APRSISRelay=false' = 'APRSISRelay=true' }
foreach ($k in $bad.Keys) {
    Write-TextFile $ini $good.Replace($k, $bad[$k])
    $r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
    Assert ($r.Code -ne 0 -and $r.Out -match 'receive-only guard') "guard refuses $($bad[$k])"
}
Write-TextFile $ini ($good -replace "PSKReporter=false`r?`n", '')
$r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
Assert ($r.Code -ne 0 -and $r.Out -match 'PSKReporter') 'guard refuses when the spotting setting is missing'
Write-TextFile $ini $good
$r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
Assert ($r.Out -notmatch 'receive-only guard') 'a receive-only profile passes the guard' $r.Out

# ------------------------------------------------------------------ JS8Call start/stop
Section 'JS8Call start and stop (stand-in program, this PC''s audio devices)'
$spk = Get-DefaultAudioDevice 'Render'; $mic = Get-DefaultAudioDevice 'Capture'
if (-not $spk -or -not $mic) { Skip 'start/stop' 'no speakers or microphone on this PC' }
else {
    Set-TestEnv @{ JS8_PLAY_DEVICE = $spk.Name; JS8_REC_DEVICE = $mic.Name }
    Write-TextFile $ini $good.Replace('SoundInName=CABLE Output', "SoundInName=$($mic.Name)").Replace('SoundOutName=CABLE Input', "SoundOutName=$($spk.Name)")
    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 24431; $listener.Start()   # stands in for JS8Call's API port
    try {
        $r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
        Assert ($r.Code -eq 0) 'start succeeds' $r.Out
        Assert ($r.Out -match 'JS8Call is up') 'waits for the API port'
        Assert ($r.Out -match 'DEFAULT playback device') 'warns when the receive device is Windows'' default output'
        $c = Get-WebSdrConfig
        Assert (@(Get-Js8Process $c).Count -eq 1) 'its JS8Call is running, found by profile name'
        $r = Invoke-Script 'bin\websdr-js8-start.ps1' @('-NoRoute', '-NoCommStat')
        Assert ($r.Out -match 'Already running') 'a second start reuses it'
        Assert (@(Get-Js8Process $c).Count -eq 1) 'still exactly one copy'
        # Another profile's JS8Call must not be touched.
        $other = Start-Process "$stubDir\js8call.exe" -ArgumentList '-r WsdrTest2' -PassThru
        $r = Invoke-Script 'bin\websdr-js8-stop.ps1'
        Assert ($r.Code -eq 0) 'stop succeeds' $r.Out
        Assert (@(Get-Js8Process $c).Count -eq 0) 'its JS8Call is gone'
        Assert (-not $other.HasExited) 'a JS8Call with another profile is left running'
        $other.Kill()
        $r = Invoke-Script 'bin\websdr-js8-stop.ps1'
        Assert ($r.Out -match 'Not running') 'stopping twice is harmless'
    } finally { $listener.Stop() }
}

# ------------------------------------------------------------------ FLDIGI settings
Section 'FLDIGI receive-only settings'
Use-Sandbox
$c = Get-WebSdrConfig
$normal = "$SANDBOX\normal-fldigi"
New-Item -ItemType Directory -Force -Path "$normal\macros", "$normal\temp", "$normal\debug" | Out-Null
$normalXml = @"
<FLDIGI_DEFS>
<MYCALL>W1AW</MYCALL>
<CHKUSEHAMLIBIS>1</CHKUSEHAMLIBIS>
<RTSPTT>1</RTSPTT>
<USEPSKREP>1</USEPSKREP>
<AUDIOIO>0</AUDIOIO>
<XMLRPC_PORT>7362</XMLRPC_PORT>
<PROG2_AUTO_ENABLE>1</PROG2_AUTO_ENABLE>
<MACROFILE>$normal\macros\macros.mdf</MACROFILE>
<OTHERPATH>$($normal -replace '\\', '/')/logs/</OTHERPATH>
</FLDIGI_DEFS>
"@
Write-TextFile "$normal\fldigi_def.xml" $normalXml
Write-TextFile "$normal\temp\junk.txt" 'x'
New-Item -ItemType Directory -Force -Path "$SANDBOX\normal-nbems\FLAMP", "$SANDBOX\normal-nbems\CUSTOM" | Out-Null
Write-TextFile "$SANDBOX\normal-nbems\FLMSG.prefs" "; FLTK preferences file format 1.0`n[.]`nmycall:W1AW`nxmlrpc_port:7362`n"
Write-TextFile "$SANDBOX\normal-nbems\CUSTOM\form.html" '<html></html>'
Write-TextFile "$SANDBOX\normal-nbems\FLAMP\FLAMP.prefs" "; FLTK`n[.]`nrepeat_forever:1`n"
$before = (Get-ChildItem -Recurse -File $normal, "$SANDBOX\normal-nbems" | Get-FileHash | ForEach-Object { $_.Hash }) -join ','
$c.CALLSIGN = 'N0CALL'; $c.GRID = 'FN31pr'
$NORMAL_FLDIGI_DIR = $normal; $NORMAL_NBEMS_DIR = "$SANDBOX\normal-nbems"
Initialize-FldigiSettings $c *> $null
Assert (Test-Path "$($c.FLDIGI_DIR)\fldigi_def.xml") 'settings copied from the normal setup'
Assert (-not (Test-Path "$($c.FLDIGI_DIR)\temp\junk.txt")) 'the copy''s temp folder is emptied'
Assert (Test-Path "$($c.NBEMS_DIR)\CUSTOM\form.html") 'FLMSG custom forms carried over'
Set-FldigiReceiveOnly $c 'CABLE Output (VB-Audio Virtual Cable)' 'Line & Out' 'C:\x\websdr-flmsg.cmd' 'C:\x\websdr-flamp.cmd'
$xmlText = [IO.File]::ReadAllText("$($c.FLDIGI_DIR)\fldigi_def.xml")
Assert ($null -eq (Test-FldigiReceiveOnly $c)) 'the result passes the guard'
foreach ($k in 'CHKUSEHAMLIBIS', 'RTSPTT', 'USEPSKREP', 'DTRPTT', 'TRANSMITRSID', 'RSIDPOST', 'PROG2_AUTO_ENABLE', 'FLAMP_AUTO_ENABLE') { Assert ((Get-XmlSetting $xmlText $k) -eq '0') "$k switched off" }
Assert ((Get-XmlSetting $xmlText 'AUDIOIO') -eq '1') 'audio through PortAudio'
Assert ((Get-XmlSetting $xmlText 'PORTINDEVICE') -eq 'CABLE Output (VB-Audio Virtual Cable)') 'records from the cable'
Assert ($xmlText -match '<PORTOUTDEVICE>Line &amp; Out</PORTOUTDEVICE>' -and (Get-XmlSetting $xmlText 'PORTOUTDEVICE') -eq 'Line & Out') 'device names are XML-escaped'
Assert ((Get-XmlSetting $xmlText 'XMLRPC_PORT') -eq '7363') 'its own XML-RPC port'
Assert ((Get-XmlSetting $xmlText 'MYCALL') -eq 'N0CALL') 'the copy gets the callsign you gave the installer'
Assert ($null -eq (Get-XmlSetting $xmlText 'RECEIVERSID')) 'a copied setup keeps its own receive RSID choice'
Assert ((Get-XmlSetting $xmlText 'MACROFILE') -eq "$($c.FLDIGI_DIR)\macros\macros.mdf") 'paths into the normal folder point at the copy (backslashes)'
Assert ((Get-XmlSetting $xmlText 'OTHERPATH') -eq "$(ConvertTo-FlPath $c.FLDIGI_DIR)logs/") 'paths into the normal folder point at the copy (forward slashes)'
Assert (([regex]::Matches($xmlText, '<RTSPTT>')).Count -eq 1) 'no duplicated settings'
Set-FldigiReceiveOnly $c 'a' 'b' 'c' 'd'
$xmlText2 = [IO.File]::ReadAllText("$($c.FLDIGI_DIR)\fldigi_def.xml")
Assert (([regex]::Matches($xmlText2, '<AUDIOIO>')).Count -eq 1) 're-applying is idempotent'
Assert ((Get-PrefSetting "$($c.NBEMS_DIR)\FLMSG.prefs" 'xmlrpc_port') -eq '7363') 'FLMSG talks to this FLDIGI'
Assert ((Get-PrefSetting "$($c.NBEMS_DIR)\FLAMP\FLAMP.prefs" 'repeat_forever') -eq '0') 'FLAMP repeats off'
Assert ((Get-PrefSetting "$($c.NBEMS_DIR)\FLAMP\FLAMP.prefs" 'socket_port') -eq '7323') 'FLAMP uses this FLDIGI''s ARQ port'
Assert (([regex]::Matches([IO.File]::ReadAllText("$($c.NBEMS_DIR)\FLAMP\FLAMP.prefs"), 'repeat_forever')).Count -eq 1) 'preference set once, not appended twice'
$after = (Get-ChildItem -Recurse -File $normal, "$SANDBOX\normal-nbems" | Get-FileHash | ForEach-Object { $_.Hash }) -join ','
Assert ($before -eq $after) 'the normal FLDIGI/NBEMS folders are untouched'
Write-TextFile "$($c.FLDIGI_DIR)\fldigi_def.xml" ($xmlText2 -replace '<RTSPTT>0</RTSPTT>', '<RTSPTT>1</RTSPTT>')
Assert ((Test-FldigiReceiveOnly $c) -match 'RTSPTT') 'guard catches PTT switched back on'
Write-TextFile "$($c.FLDIGI_DIR)\fldigi_def.xml" ($xmlText2 -replace '<AUDIOIO>1</AUDIOIO>', '<AUDIOIO>3</AUDIOIO>')
Assert ((Test-FldigiReceiveOnly $c) -match 'PortAudio') 'guard catches the audio back end changed'
# Fresh settings when there is no normal FLDIGI.
Remove-Item -Recurse -Force $c.FLDIGI_DIR, $c.NBEMS_DIR
$NORMAL_FLDIGI_DIR = "$SANDBOX\does-not-exist"; $NORMAL_NBEMS_DIR = "$SANDBOX\does-not-exist-either"
Initialize-FldigiSettings $c *> $null
$xmlText = [IO.File]::ReadAllText("$($c.FLDIGI_DIR)\fldigi_def.xml")
Assert ((Get-XmlSetting $xmlText 'MYCALL') -eq 'N0CALL' -and (Get-XmlSetting $xmlText 'MYLOC') -eq 'FN31pr') 'fresh settings get your callsign and grid'
Assert ((Get-XmlSetting $xmlText 'RECEIVERSID') -eq '1' -and (Get-XmlSetting $xmlText 'RSIDAUTODISABLE') -eq '0' -and (Get-XmlSetting $xmlText 'RSIDNOTIFYONLY') -eq '0') 'fresh settings follow mode changes (receive RSID on)'
Set-FldigiReceiveOnly $c 'a' 'b' 'c' 'd'
Assert ($null -eq (Test-FldigiReceiveOnly $c)) 'fresh settings pass the guard (every key added, nothing left to a default)'
$xmlText = [IO.File]::ReadAllText("$($c.FLDIGI_DIR)\fldigi_def.xml")
Assert ((Get-XmlSetting $xmlText 'RECEIVERSID') -eq '1' -and (Get-XmlSetting $xmlText 'TRANSMITRSID') -eq '0' -and (Get-XmlSetting $xmlText 'RSIDPOST') -eq '0') 'receive RSID survives the receive-only settings; transmit RSID stays off'
Assert ((Get-PrefSetting "$($c.NBEMS_DIR)\FLMSG.prefs" 'mycall') -eq 'N0CALL') 'fresh FLMSG settings get your callsign'

# ------------------------------------------------------------------ audio sessions
Section 'Audio session detection'
if (-not $spk) { Skip 'session detection' 'no speakers' }
else {
    $wav = "$SANDBOX\silence.wav"; $n = 44100 * 3
    $bw = New-Object IO.BinaryWriter ([IO.File]::Create($wav))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $n * 2)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]44100); $bw.Write([int]88200); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]($n * 2)); $bw.Write((New-Object byte[] ($n * 2))); $bw.Close()
    $sp = New-Object Media.SoundPlayer $wav; $sp.PlayLooping(); Start-Sleep -Milliseconds 1500    # silence: nothing is heard
    $me = (Get-Process -Id $PID).ProcessName
    Assert (@(Get-AudioPlayers $spk -ActiveOnly | Where-Object { $_.ProcessId -eq $PID }).Count -eq 1) 'a playing program is seen on its device'
    Assert (@(Get-AudioPlayers $spk @($me) -ActiveOnly | Where-Object { $_.ProcessId -eq $PID }).Count -eq 0) 'excluded programs (the decoders themselves) are left out'
    $sp.Stop(); Start-Sleep -Milliseconds 800
    Assert (@(Get-AudioPlayers $spk -ActiveOnly | Where-Object { $_.ProcessId -eq $PID }).Count -eq 0) 'stopped audio is no longer counted as playing'
    Assert (Test-SameDeviceName 'CABLE Input (VB-Audio Virtual ' 'CABLE Input (VB-Audio Virtual Cable)') 'a name cut to 31 characters still matches'
    Assert (-not (Test-SameDeviceName 'Speakers' 'CABLE Input (VB-Audio Virtual Cable)')) 'a different device does not match'
}

# ------------------------------------------------------------------ preflight
Section 'Prerequisite check'
Use-Sandbox
Set-TestEnv @{ TCP_PORT = '80' }
$r = Invoke-Script 'preflight.ps1' @('-NoNetwork')
Assert ($r.Code -eq 1 -and $r.Out -match 'FAIL\] Setting: TCP_PORT') 'an invalid port is a FAIL'
Assert ($r.Out -match 'Read-only') 'it says it changes nothing'
$listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 24432; $listener.Start()
try {
    Set-TestEnv @{ TCP_PORT = '24432' }
    $r = Invoke-Script 'preflight.ps1' @('-NoNetwork', '-Quiet')
    Assert ($r.Out -match 'FAIL\] TCP port 24432') 'a port already in use is a FAIL'
} finally { $listener.Stop() }
Set-TestEnv @{ TCP_PORT = '24431'; JS8_PLAY_DEVICE = 'No Such Cable'; JS8_REC_DEVICE = 'No Such Cable' }
$r = Invoke-Script 'preflight.ps1' @('-NoNetwork', '-NoFldigi')
Assert ($r.Code -eq 1 -and $r.Out -match 'FAIL\] Cable \(JS8Call\)' -and $r.Out -match 'vb-audio.com') 'a missing virtual cable is a FAIL, with where to get one'
Remove-Item -Recurse -Force "$SANDBOX\config" -ErrorAction SilentlyContinue
$r = Invoke-Script 'install.ps1' @('-Check', '-NoNetwork', '-NoFldigi')
Assert ($r.Code -eq 1 -and $r.Out -match 'Nothing was installed or changed') 'the installer stops before changing anything'
Assert (-not (Test-Path "$SANDBOX\config\config")) 'no settings were written'
if ($spk -and $mic) {
    Set-TestEnv @{ JS8_PLAY_DEVICE = $spk.Name; JS8_REC_DEVICE = $mic.Name }
    $r = Invoke-Script 'preflight.ps1' @('-NoNetwork', '-NoFldigi')
    Assert ($r.Out -match 'OK  \] Cable \(JS8Call\)') 'configured devices are found by name' $r.Out
}

# ------------------------------------------------------------------ uninstall
Section 'Uninstall'
Use-Sandbox
$c = Get-WebSdrConfig
foreach ($d in $c.BIN_DIR, $c.APP_DIR, $c.CONFIG_DIR, $c.JS8_HOME, $c.COMMSTAT_DIR, $c.FLDIGI_DIR, $c.NBEMS_DIR, "$SANDBOX\normal-fldigi") { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Write-TextFile "$($c.CONFIG_DIR)\config" "PROFILE=WsdrTest`r`n"
New-Item -ItemType Directory -Force -Path $c.DESKTOP_DIR | Out-Null
New-StationShortcuts $c $true $true *> $null
Assert ((@(Get-ChildItem "$($c.MENU_DIR)\*.lnk").Count -eq 4) -and (@(Get-ChildItem "$($c.DESKTOP_DIR)\*.lnk").Count -eq 4)) 'shortcuts created in the (sandboxed) Start Menu and Desktop'
$realMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'WebSDR Digital Receive-Only'
$realBefore = Test-Path $realMenu
$r = Invoke-Script 'uninstall.ps1' @('-KeepData')
Assert (-not (Test-Path $c.MENU_DIR) -and @(Get-ChildItem "$($c.DESKTOP_DIR)\*.lnk" -ErrorAction SilentlyContinue).Count -eq 0) 'uninstall removes the shortcuts'
Assert ((Test-Path $realMenu) -eq $realBefore) 'the real Start Menu folder is never touched by the tests'
Assert ($r.Code -eq 0) 'uninstall -KeepData succeeds' $r.Out
Assert (-not (Test-Path $c.BIN_DIR) -and -not (Test-Path $c.APP_DIR) -and -not (Test-Path $c.CONFIG_DIR)) 'launchers, app files and settings removed'
Assert ((Test-Path $c.JS8_HOME) -and (Test-Path $c.COMMSTAT_DIR) -and (Test-Path $c.FLDIGI_DIR)) '-KeepData keeps the data'
$r = Invoke-Script 'uninstall.ps1' @('-Purge')
Assert (-not (Test-Path $c.JS8_HOME) -and -not (Test-Path $c.COMMSTAT_DIR) -and -not (Test-Path $c.FLDIGI_DIR) -and -not (Test-Path $c.NBEMS_DIR)) '-Purge removes the data'
Assert (Test-Path "$SANDBOX\normal-fldigi") 'a normal FLDIGI folder is never touched'

} finally {
    Clear-TestEnv
    Get-Process js8call -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$SANDBOX*" } | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    Remove-Item -Recurse -Force $SANDBOX -ErrorAction SilentlyContinue
}

Write-Host ("`n{0} passed, {1} failed, {2} skipped" -f $script:pass, $script:fail, $script:skip) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 } else { exit 0 }
