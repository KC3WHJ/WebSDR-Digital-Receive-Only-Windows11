# Shared helpers for install.ps1, preflight.ps1, uninstall.ps1 and the launchers.
# Dot-source this file; it does nothing on its own. Windows PowerShell 5.1 or later.

$WEBSDR_JS8_VERSION = "0.2.0-win"

function Write-Info([string]$Text = "") { Write-Host $Text }
function Write-Step([string]$Text) { Write-Host ""; Write-Host "==> $Text" -ForegroundColor White }
function Write-Warn([string]$Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Fail([string]$Text) { Write-Host "ERROR: $Text" -ForegroundColor Red; Exit-Script 1 }

# Launched from a Start Menu / Desktop shortcut (-Pause): keep the window open at the end
# so its messages can be read.
function Exit-Script([int]$Code = 0) {
    if ($global:WEBSDR_PAUSE -and (Test-Interactive)) { [void](Read-Host "`nPress Enter to close this window") }
    exit $Code
}

# Print a script's opening <# ... #> comment as its --help text.
function Show-ScriptHelp([string]$Path) {
    $in = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if (-not $in) { if ($line -eq '<#') { $in = $true }; continue }
        if ($line -eq '#>') { break }
        Write-Host $line
    }
}

# True when there is someone at the keyboard to answer a question.
function Test-Interactive { -not [Console]::IsInputRedirected -and [Environment]::UserInteractive }

# Files that other programs read (JS8Call, FLDIGI, Python) must not get a byte-order mark.
function Write-TextFile([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

# ---------------------------------------------------------------- settings
# Defaults, then %APPDATA%\websdr-js8\config, then WEBSDR_JS8_* environment variables
# (used by the test suite, and handy for a second, separate profile). The config file is
# read as plain KEY=VALUE lines against a whitelist - it is never executed.
$CONFIG_KEYS = @(
    'PROFILE', 'TCP_PORT', 'UDP_PORT', 'COMMSTAT_DIR', 'CALLSIGN', 'GRID', 'STATE',
    'JS8_PLAY_DEVICE', 'JS8_REC_DEVICE', 'JS8_TX_DEVICE',
    'FLDIGI_DIR', 'NBEMS_DIR', 'FL_PLAY_DEVICE', 'FL_REC_DEVICE', 'FL_TX_DEVICE',
    'FL_XMLRPC_PORT', 'FL_ARQ_PORT', 'FL_KISS_IO_PORT', 'FL_KISS_OUT_PORT',
    'JS8CALL_EXE', 'FLDIGI_EXE', 'FLMSG_EXE', 'FLAMP_EXE', 'PYTHON', 'COMMSTAT_SCALE'
)

function Get-WebSdrConfig {
    $configDir = if ($env:WEBSDR_JS8_CONFIG_DIR) { $env:WEBSDR_JS8_CONFIG_DIR } else { Join-Path $env:APPDATA 'websdr-js8' }
    $dataDir   = if ($env:WEBSDR_JS8_DATA_DIR)   { $env:WEBSDR_JS8_DATA_DIR }   else { Join-Path $env:LOCALAPPDATA 'websdr-js8' }
    $c = [ordered]@{
        CONFIG_DIR       = $configDir
        DATA_DIR         = $dataDir
        PROFILE          = 'WebSDR'          # JS8Call profile name: js8call -r <PROFILE>
        TCP_PORT         = '2443'            # JS8Call's TCP API port that CommStat connects to
        UDP_PORT         = '2238'            # JS8Call's UDP API port (unused, but kept off the defaults)
        COMMSTAT_DIR     = (Join-Path $dataDir 'CommStat')
        CALLSIGN = ''; GRID = ''; STATE = ''
        # Virtual audio cable for the JS8Call station. A cable has two ends: the browser
        # PLAYS into its playback end, and the decoder RECORDS from its recording end.
        # Names match exactly or by their beginning ("CABLE Input" matches
        # "CABLE Input (VB-Audio Virtual Cable)").
        JS8_PLAY_DEVICE  = 'CABLE Input'
        JS8_REC_DEVICE   = 'CABLE Output'
        JS8_TX_DEVICE    = ''                # where JS8Call's *transmit* audio goes; blank = JS8_PLAY_DEVICE
        # FLDIGI + FLMSG + FLAMP station: its own settings folders and ports, so it never
        # touches a normal (radio) FLDIGI setup and can run beside it.
        FLDIGI_DIR       = (Join-Path $env:USERPROFILE 'fldigi-websdr.files')   # fldigi --config-dir
        NBEMS_DIR        = (Join-Path $env:USERPROFILE 'NBEMS-websdr.files')    # FLMSG folder (FLAMP uses its FLAMP\ subfolder)
        FL_PLAY_DEVICE   = 'CABLE Input'     # same cable by default: one station at a time
        FL_REC_DEVICE    = 'CABLE Output'    # (set a second cable here to run both at once)
        FL_TX_DEVICE     = ''
        FL_XMLRPC_PORT   = '7363'            # a normal FLDIGI uses 7362
        FL_ARQ_PORT      = '7323'            # normally 7322
        FL_KISS_IO_PORT  = '7344'
        FL_KISS_OUT_PORT = '7345'
        # Program locations; blank = find them automatically.
        JS8CALL_EXE = ''; FLDIGI_EXE = ''; FLMSG_EXE = ''; FLAMP_EXE = ''
        PYTHON           = (Join-Path $dataDir 'venv\Scripts\python.exe')       # CommStat's own Python environment
        # Draw CommStat smaller (e.g. 0.8) on a screen too small for its window; blank = normal.
        COMMSTAT_SCALE   = ''
    }
    $file = Join-Path $configDir 'config'
    if (Test-Path -LiteralPath $file) {
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line -match '^\s*(#|$)') { continue }
            $i = $line.IndexOf('=')
            if ($i -lt 1) { continue }
            $k = $line.Substring(0, $i).Trim(); $v = $line.Substring($i + 1).Trim()
            if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            if ($CONFIG_KEYS -contains $k) { $c[$k] = $v }
        }
    }
    foreach ($k in $CONFIG_KEYS) {   # environment overrides win
        $e = [Environment]::GetEnvironmentVariable("WEBSDR_JS8_$k")
        if ($e) { $c[$k] = $e }
    }
    if (-not $c.JS8_TX_DEVICE) { $c.JS8_TX_DEVICE = $c.JS8_PLAY_DEVICE }
    if (-not $c.FL_TX_DEVICE)  { $c.FL_TX_DEVICE  = $c.FL_PLAY_DEVICE }
    # JS8Call (Qt) keeps a profile's settings in %LOCALAPPDATA%\JS8Call - <profile>\.
    $js8Home = if ($env:WEBSDR_JS8_JS8_HOME) { $env:WEBSDR_JS8_JS8_HOME } else { Join-Path $env:LOCALAPPDATA "JS8Call - $($c.PROFILE)" }
    $c.JS8_HOME = $js8Home
    $c.JS8_INI  = Join-Path $js8Home "JS8Call - $($c.PROFILE).ini"
    $c.BIN_DIR  = Join-Path $dataDir 'bin'
    $c.APP_DIR  = Join-Path $dataDir 'app'
    # Where the shortcuts go (overridable so the tests never touch the real ones).
    $c.MENU_DIR    = if ($env:WEBSDR_JS8_MENU_DIR) { $env:WEBSDR_JS8_MENU_DIR } else { Join-Path ([Environment]::GetFolderPath('Programs')) 'WebSDR Digital Receive-Only' }
    $c.DESKTOP_DIR = if ($env:WEBSDR_JS8_DESKTOP_DIR) { $env:WEBSDR_JS8_DESKTOP_DIR } else { [Environment]::GetFolderPath('Desktop') }
    return $c
}

# Writes the current settings back out (used by the installer).
function Save-WebSdrConfig($c) {
    $lines = @(
        '# WebSDR-Digital-Receive-Only (Windows) settings. Plain KEY=VALUE lines; edit and'
        '# restart a station to apply. Environment variables named WEBSDR_JS8_<KEY> override these.'
    )
    foreach ($k in $CONFIG_KEYS) { $lines += "$k=$($c[$k])" }
    Write-TextFile (Join-Path $c.CONFIG_DIR 'config') (($lines -join "`r`n") + "`r`n")
}

# -------------------------------------------------------------- validation
# Deliberately loose: a licensed call (W1AW, W1AW/P), or any short tactical / placeholder
# ID (N0CALL) for someone who is only listening.
function Test-Callsign([string]$v) { $v -cmatch '^[A-Za-z0-9/]{3,12}$' }
function Test-Grid([string]$v)     { $v -match '^[A-R]{2}[0-9]{2}([A-X]{2})?$' }
function Test-State([string]$v)    { (-not $v) -or ($v -match '^[A-Z]{2}$') }
function Test-Port([string]$v)     { ($v -match '^[0-9]{1,5}$') -and ([int]$v -ge 1024) -and ([int]$v -le 65535) }
function Test-ProfileName([string]$v) { $v -match '^[A-Za-z0-9_]+$' }
function Test-DeviceName([string]$v)  { ($v.Length -ge 1) -and ($v.Length -le 100) -and ($v -notmatch '["\r\n=]') }

# Callsign/state upper case; grid in Maidenhead convention (FN31pr).
function Format-Grid([string]$g) {
    $g = $g.ToUpper()
    if ($g.Length -gt 4) { $g = $g.Substring(0, 4) + $g.Substring(4).ToLower() }
    return $g
}

# ----------------------------------------------------------- small helpers
function Test-PortInUse([string]$Port) {
    $null -ne (Get-NetTCPConnection -State Listen -LocalPort ([int]$Port) -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Wait-Port([string]$Port, [int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) { if (Test-PortInUse $Port) { return $true }; Start-Sleep -Seconds 1 }
    return (Test-PortInUse $Port)
}

# Read one key from a JS8Call .ini file (first match wins; empty if absent).
function Get-IniValue([string]$File, [string]$Key) {
    if (-not (Test-Path -LiteralPath $File)) { return '' }
    foreach ($line in [IO.File]::ReadAllLines($File)) {
        if ($line.StartsWith("$Key=")) { return $line.Substring($Key.Length + 1) }
    }
    return ''
}

# Quote one argument for a Windows command line (CommandLineToArgvW rules).
function ConvertTo-Arg([string]$a) {
    if ($a -notmatch '[\s"]' -and $a.Length -gt 0) { return $a }
    $a = $a -replace '(\\*)"', '$1$1\"'
    $a = $a -replace '(\\+)$', '$1$1'
    return '"' + $a + '"'
}
function Join-Args([string[]]$Items) { ($Items | ForEach-Object { ConvertTo-Arg $_ }) -join ' ' }

# Run a program in this window and return its exit code. Unlike "& prog args", empty
# arguments survive (Windows PowerShell 5.1 silently drops them).
function Invoke-Native([string]$Exe, [string[]]$Arguments, [string]$WorkDir = '') {
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, (Join-Args $Arguments)
    $psi.UseShellExecute = $false
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $p = [Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    return $p.ExitCode
}

# Tell Explorer (and so newly opened windows) that the user's environment changed.
function Send-EnvironmentChanged {
    if (-not ('WebSdrNative.Env' -as [type])) {
        Add-Type -Namespace WebSdrNative -Name Env -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $r = [UIntPtr]::Zero
    [void][WebSdrNative.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 3000, [ref]$r)
}

# A folder path in the form FLDIGI/FLMSG/FLAMP want on their command line: forward
# slashes and a trailing slash (a trailing backslash would swallow the closing quote).
function ConvertTo-FlPath([string]$Dir) { ($Dir -replace '\\', '/').TrimEnd('/') + '/' }

# Locate an installed program. Order: the *_EXE setting, PATH, then the folders its
# Windows installer uses (newest version first).
function Find-Program([string]$Name, [string]$Configured) {
    if ($Configured) { if (Test-Path -LiteralPath $Configured) { return $Configured } else { return $null } }
    $cmd = Get-Command "$Name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ }
    $patterns = switch ($Name) {
        'js8call' { @('js8call\bin\js8call.exe', 'JS8Call*\bin\js8call.exe', 'js8call\js8call.exe') }
        default   { @("$Name*\$Name.exe") }
    }
    foreach ($r in $roots) {
        foreach ($p in $patterns) {
            $hit = Get-ChildItem -Path (Join-Path $r $p) -ErrorAction SilentlyContinue |
                   Sort-Object { $_.Directory.FullName } -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

# Processes whose image name is $Name and whose command line contains $Contains
# (case-insensitive, plain text).
function Get-StationProcess([string[]]$Name, [string]$Contains) {
    $filter = ($Name | ForEach-Object { "Name='$_'" }) -join ' OR '
    Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Contains, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
}

# This install's own copies of each program, told apart from a normal (radio) setup by the
# profile / settings folder on their command line.
function Get-Js8Process($c)      { Get-StationProcess @('js8call.exe') "-r $($c.PROFILE)" | Where-Object { $_.CommandLine -match "-r\s+`"?$($c.PROFILE)`"?(\s|$)" } }
function Get-CommStatProcess($c) { Get-StationProcess @('python.exe', 'pythonw.exe') (Join-Path $c.COMMSTAT_DIR '') }
function Get-FldigiProcess($c)   { Get-StationProcess @('fldigi.exe') (ConvertTo-FlPath $c.FLDIGI_DIR) }
function Get-FlmsgProcess($c)    { Get-StationProcess @('flmsg.exe') (ConvertTo-FlPath $c.NBEMS_DIR) }
function Get-FlampProcess($c)    { Get-StationProcess @('flamp.exe') (ConvertTo-FlPath $c.NBEMS_DIR) }

# Close processes politely (their main window gets a close request, so they save their
# settings), then forcibly - with their child processes - if they're still there.
# $Find is a script block returning the processes, e.g. { Get-Js8Process $c }.
function Wait-Gone([scriptblock]$Find, [int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) { if (@(& $Find).Count -eq 0) { return $true }; Start-Sleep -Seconds 1 }
    return (@(& $Find).Count -eq 0)
}
function Stop-StationProcess([string]$Label, [scriptblock]$Find, [int]$Seconds = 10, [switch]$SkipPolite) {
    Write-Step "Stopping $Label"
    $procs = @(& $Find)
    if ($procs.Count -eq 0) { Write-Info "Not running."; return }
    if (-not $SkipPolite) {
        foreach ($p in $procs) { try { [void](Get-Process -Id $p.ProcessId -ErrorAction Stop).CloseMainWindow() } catch { } }
        if (Wait-Gone $Find $Seconds) { Write-Info "Stopped."; return }
    }
    foreach ($p in @(& $Find)) { & taskkill.exe /T /F /PID $p.ProcessId 2>$null | Out-Null }
    [void](Wait-Gone $Find 5)
    Write-Info "Stopped (forced)."
}

# Start a program detached from this window: closing the console does not close it.
function Start-Detached([string]$Exe, [string[]]$Arguments, [string]$WorkDir, [string]$Log) {
    $sp = @{ FilePath = $Exe; PassThru = $true }
    if ($Arguments -and $Arguments.Count) { $sp.ArgumentList = (Join-Args $Arguments) }
    if ($WorkDir) { $sp.WorkingDirectory = $WorkDir }
    if ($Log) { $sp.RedirectStandardOutput = $Log; $sp.RedirectStandardError = "$Log.err" }
    Start-Process @sp
}

# ------------------------------------------------------------ shortcuts
$SHORTCUT_NAMES = @('Start WebSDR JS8Call + CommStat', 'Stop WebSDR JS8Call + CommStat', 'Start WebSDR FLDIGI + FLMSG-FLAMP', 'Stop WebSDR FLDIGI + FLMSG-FLAMP')

# Start Menu (and Desktop) shortcuts that run the installed launchers in a window that
# stays open at the end (-Pause), so their messages can be read.
function New-StationShortcuts($c, [bool]$WithFldigi, [bool]$Desktop) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shell = New-Object -ComObject WScript.Shell
    $js8Exe = Find-Program 'js8call' $c.JS8CALL_EXE; $flExe = Find-Program 'fldigi' $c.FLDIGI_EXE
    $stopIcon = "$env:SystemRoot\System32\shell32.dll,131"
    $links = @(
        @{ Name = $SHORTCUT_NAMES[0]; Cmd = 'websdr-js8-start'; Desc = 'Receive-only JS8Call and CommStat fed by a web SDR'; Icon = $(if ($js8Exe) { "$js8Exe,0" } else { '' }) },
        @{ Name = $SHORTCUT_NAMES[1]; Cmd = 'websdr-js8-stop'; Desc = 'Stops the receive-only JS8Call station'; Icon = $stopIcon })
    if ($WithFldigi) {
        $links += @{ Name = $SHORTCUT_NAMES[2]; Cmd = 'websdr-fldigi-start'; Desc = 'Receive-only FLDIGI, FLMSG and FLAMP fed by a web SDR'; Icon = $(if ($flExe) { "$flExe,0" } else { '' }) }
        $links += @{ Name = $SHORTCUT_NAMES[3]; Cmd = 'websdr-fldigi-stop'; Desc = 'Stops the receive-only FLDIGI station'; Icon = $stopIcon }
    }
    New-Item -ItemType Directory -Force -Path $c.MENU_DIR | Out-Null
    foreach ($l in $links) {
        $s = $shell.CreateShortcut((Join-Path $c.MENU_DIR "$($l.Name).lnk"))
        $s.TargetPath = $ps
        $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $c.APP_DIR "bin\$($l.Cmd).ps1")`" -Pause"
        $s.WorkingDirectory = $env:USERPROFILE
        $s.Description = $l.Desc
        if ($l.Icon) { $s.IconLocation = $l.Icon }
        $s.Save()
    }
    Write-Info "Added the launchers to the Start Menu ($($c.MENU_DIR))."
    if ($Desktop) {
        foreach ($l in $links) { Copy-Item -Force (Join-Path $c.MENU_DIR "$($l.Name).lnk") $c.DESKTOP_DIR }
        Write-Info "Added Desktop shortcuts ($($c.DESKTOP_DIR))."
    }
}

# ------------------------------------------------------------ audio devices
# Windows has no built-in "null sink", so a virtual audio cable driver (VB-CABLE, or any
# other) stands in for one. lib\AudioHelper.cs reads devices and audio sessions through the
# documented Core Audio API; it never changes an audio setting.
function Initialize-Audio {
    if (-not ('WebSdrAudio.Audio' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'AudioHelper.cs')))
    }
}

# flow: 'Render' (playback) or 'Capture' (recording). Exact name first, then by beginning.
function Find-AudioDevice([string]$Name, [string]$Flow) {
    Initialize-Audio
    $list = [WebSdrAudio.Audio]::GetEndpoints($(if ($Flow -eq 'Render') { 0 } else { 1 }))
    $hit = $list | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $hit) { $hit = $list | Where-Object { $_.Name.StartsWith($Name, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 }
    return $hit
}

function Get-DefaultAudioDevice([string]$Flow) {
    Initialize-Audio
    [WebSdrAudio.Audio]::GetDefault($(if ($Flow -eq 'Render') { 0 } else { 1 }))
}

# Programs (other than the decoders themselves) that have audio on a playback device.
function Get-AudioPlayers($Device, [string[]]$Exclude = @(), [switch]$ActiveOnly) {
    Initialize-Audio
    [WebSdrAudio.Audio]::GetSessions($Device.Id) |
        Where-Object { ($Exclude -notcontains $_.ProcessName) -and ((-not $ActiveOnly) -or $_.Active) }
}

# Some apps report a device name cut to 31 characters (the old MME limit). True if the two
# names are the same device either way.
function Test-SameDeviceName([string]$Saved, [string]$Full) {
    if (-not $Saved -or -not $Full) { return $false }
    return $Full.StartsWith($Saved, [StringComparison]::OrdinalIgnoreCase) -or $Saved.StartsWith($Full, [StringComparison]::OrdinalIgnoreCase)
}

$DECODER_PROCESSES = @('js8call', 'fldigi', 'flmsg', 'flamp')

# ------------------------------------------------------------ audio routing
# Windows chooses an output device PER PROGRAM (Settings > System > Sound > Volume mixer),
# not per browser tab, and offers no supported way for a script to change it. So this
# opens that page, tells you what to pick, and then checks - by listing who is actually
# playing into the cable - that it worked. Shared by both start scripts.
# Returns $true when a stream is routed (or already was).
function Invoke-BrowserRouting($PlayDevice, [string]$App, [string]$Hint, [string]$StartCmd, [string]$StopCmd) {
    Write-Step "Route your WebSDR's audio into $App"
    $now = @(Get-AudioPlayers $PlayDevice $DECODER_PROCESSES -ActiveOnly)
    if ($now.Count -gt 0) {
        Write-Info "Already routed: $(($now | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', ') is playing into '$($PlayDevice.Name)'."
        Write-Info ""; Write-Info "When you're finished: $StopCmd"; return $true
    }
    if (-not (Test-Interactive)) {
        Write-Info "No one to ask (not an interactive window) - route the audio yourself, then run $StartCmd again to check."
        return $false
    }
    Write-Info @"
1. In your browser, open a web SDR or KiwiSDR and start its audio playing.
   $Hint
2. In the Settings window that opens now (System > Sound > Volume mixer), find your
   browser under "Apps" and set its Output device to:
       $($PlayDevice.Name)
   Windows applies this to the whole browser, not one tab, so use a browser you don't
   need for anything else while you listen (for example Firefox if you normally use Edge).
3. Come back here and press Enter.
"@
    try { Start-Process 'ms-settings:apps-volume' } catch { Write-Warn "couldn't open Settings - open Settings > System > Sound > Volume mixer yourself." }
    while ($true) {
        $ans = Read-Host "Press Enter to check (or type q to skip)"
        if ($ans -match '^[qQ]') { Write-Info "Skipped. Run $StartCmd again once the audio is routed (it's safe to re-run)."; return $false }
        $now = @(Get-AudioPlayers $PlayDevice $DECODER_PROCESSES -ActiveOnly)
        if ($now.Count -gt 0) { break }
        Write-Info "Nothing is playing into '$($PlayDevice.Name)' yet. Is the WebSDR's audio playing, and is the browser's Output set to that device?"
    }
    $names = ($now | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Info "Routed: $names is playing into '$($PlayDevice.Name)'. $App should start decoding shortly."
    Write-Info "You won't hear the WebSDR now - that's expected."
    Write-Info ""; Write-Info "When you're finished: $StopCmd"
    return $true
}

# After a station stops: anything still set to play into the cable plays into nothing.
function Show-RoutingReminder($PlayDevice) {
    if (-not $PlayDevice) { return }
    $left = @(Get-AudioPlayers $PlayDevice $DECODER_PROCESSES)
    if ($left.Count -eq 0) { return }
    $names = ($left | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Info ""
    Write-Info "$names is still set to play into '$($PlayDevice.Name)', so you won't hear it."
    Write-Info "In the Volume mixer (opening now), set its Output device back to Default."
    if (Test-Interactive) { try { Start-Process 'ms-settings:apps-volume' } catch { } }
}
