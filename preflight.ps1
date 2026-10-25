<#
Prerequisite check for WebSDR-Digital-Receive-Only (Windows).

Read-only: it installs nothing, changes nothing, and never asks for administrator rights.
install.ps1 runs this first and refuses to touch your system if anything is marked FAIL.
You can also run it by itself as a dry run:

    .\preflight.cmd                  full check
    .\preflight.cmd -Quiet           only show warnings and failures
    .\preflight.cmd -NoNetwork       skip the internet checks (offline test)
    .\preflight.cmd -NoFldigi        leave out the FLDIGI station's checks

Exit status: 0 = ready to install (warnings allowed), 1 = at least one FAIL.
#>
[CmdletBinding()]
param([switch]$Quiet, [switch]$NoNetwork, [switch]$NoFldigi, [switch]$SkipWinget, [switch]$Help)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:PF = @{ Quiet = [bool]$Quiet; Network = -not $NoNetwork; Fldigi = -not $NoFldigi; Winget = -not $SkipWinget }
$script:N_OK = 0; $script:N_WARN = 0; $script:N_FAIL = 0

# Add-Result LEVEL "Label" "detail" ["how to fix"]
function Add-Result([string]$Level, [string]$Label, [string]$Detail, [string]$Hint = '') {
    switch ($Level) {
        'OK'   { $script:N_OK++;   $color = 'Green' }
        'WARN' { $script:N_WARN++; $color = 'Yellow' }
        'FAIL' { $script:N_FAIL++; $color = 'Red' }
    }
    if ($Level -eq 'OK' -and $script:PF.Quiet) { return }
    Write-Host ('  [{0,-4}] ' -f $Level) -ForegroundColor $color -NoNewline
    Write-Host ('{0,-26} {1}' -f $Label, $Detail)
    if ($Hint) { Write-Host "         -> $Hint" -ForegroundColor DarkGray }
}

function Test-TcpReachable([string]$TargetHost, [int]$Port, [int]$TimeoutMs = 6000) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar); return $true
    } catch { return $false } finally { $c.Close() }
}

# Offset of this PC's clock from an NTP server, in seconds (positive = PC is ahead), or $null.
function Get-ClockOffset([string]$Server = 'time.windows.com') {
    $u = New-Object Net.Sockets.UdpClient
    try {
        $u.Client.ReceiveTimeout = 3000
        $req = New-Object byte[] 48; $req[0] = 0x1B           # NTP v3, client mode
        $t1 = [DateTime]::UtcNow
        [void]$u.Send($req, 48, $Server, 123)
        $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any), 0
        $r = $u.Receive([ref]$ep)
        $t4 = [DateTime]::UtcNow
        # Transmit timestamp: seconds since 1900 (big-endian), bytes 40-47.
        $sec = [uint64](([uint64]$r[40] -shl 24) -bor ([uint64]$r[41] -shl 16) -bor ([uint64]$r[42] -shl 8) -bor $r[43])
        $frac = [uint64](([uint64]$r[44] -shl 24) -bor ([uint64]$r[45] -shl 16) -bor ([uint64]$r[46] -shl 8) -bor $r[47])
        $theirs = (New-Object DateTime 1900, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)).AddSeconds($sec + $frac / 4294967296.0)
        $mid = $t1.AddTicks([long](($t4 - $t1).Ticks / 2))
        return ($mid - $theirs).TotalSeconds
    } catch { return $null } finally { $u.Close() }
}

# A Python 3.8+ that isn't the Microsoft Store placeholder. Returns its path, or $null.
function Find-BasePython {
    $cands = @()
    foreach ($n in 'py', 'python', 'python3') {
        Get-Command "$n.exe" -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $cands += $_.Source }
    }
    $cands += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
    foreach ($p in $cands) {
        $a = if ((Split-Path -Leaf $p) -eq 'py.exe') { @('-3') } else { @() }
        $out = & $p @a -c "import sys; print(sys.executable if sys.version_info >= (3, 8) else '')" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path -LiteralPath "$out".Trim())) { return "$out".Trim() }
    }
    return $null
}

# ------------------------------------------------------------------ checks
function Test-OS {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $build = [Environment]::OSVersion.Version.Build
    $name = if ($os) { "$($os.Caption) (build $build)" } else { "Windows build $build" }
    if ($build -ge 22000)     { Add-Result OK   'Operating system' $name }
    elseif ($build -ge 17763) { Add-Result WARN 'Operating system' $name 'Written for Windows 11; Windows 10 should work but is untested.' }
    else                      { Add-Result FAIL 'Operating system' $name 'Windows 10 1809 or newer is needed (winget and the audio settings page).' }
    if ($PSVersionTable.PSVersion -ge [version]'5.1') { Add-Result OK 'PowerShell' "$($PSVersionTable.PSVersion)" }
    else { Add-Result FAIL 'PowerShell' "$($PSVersionTable.PSVersion)" 'PowerShell 5.1 or newer is needed.' }
}

function Test-Arch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { Add-Result OK 'CPU architecture' $arch }
        'ARM64' { Add-Result WARN 'CPU architecture' $arch 'FLDIGI runs under x86 emulation; make sure your virtual audio cable driver has an ARM64 build.' }
        default { Add-Result WARN 'CPU architecture' $arch 'Only 64-bit Windows has been considered.' }
    }
}

function Test-User {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) {
        Add-Result FAIL 'Running as' "$($id.Name) (Administrator window)" 'Run from a normal, non-administrator PowerShell or Terminal. The settings are per user, and winget asks for administrator rights itself where a program needs them.'
    } else {
        Add-Result OK 'Running as' "$($id.Name) (not elevated)"
    }
    if ($env:SSH_CONNECTION) { Add-Result FAIL 'Desktop session' 'connected over SSH' 'JS8Call, FLDIGI and CommStat are desktop apps, and audio routing needs your logged-in desktop. Run this from a window on the desktop.' }
}

function Test-Winget {
    if (-not $script:PF.Winget) { Add-Result WARN 'winget' 'skipped (-SkipWinget)' 'You install JS8Call, FLDIGI, FLMSG, FLAMP and Python yourself.'; return }
    $w = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($w) { Add-Result OK 'winget' "$((& winget.exe --version 2>$null) -join '')" }
    else { Add-Result FAIL 'winget' 'not found' "Install or update 'App Installer' from the Microsoft Store, or run the installer with -SkipWinget after installing the programs yourself." }
}

function Test-Resources {
    $drives = @(@{ Label = 'system'; Letter = $env:SystemDrive.TrimEnd(':') }, @{ Label = 'profile'; Letter = $env:LOCALAPPDATA.Substring(0, 1) })
    $parts = @(); $low = $false
    foreach ($d in $drives) {
        $free = (Get-PSDrive -Name $d.Letter -ErrorAction SilentlyContinue).Free
        $mb = if ($free) { [int]($free / 1MB) } else { 0 }
        $parts += "$mb MiB free on $($d.Letter): ($($d.Label))"
        if ($mb -lt 1536) { $low = $true }
    }
    $detail = ($parts | Select-Object -Unique) -join ', '
    if ($low) { Add-Result FAIL 'Disk space' $detail 'Need about 1.5 GiB free (CommStat''s Qt WebEngine is large).' }
    else      { Add-Result OK   'Disk space' $detail }
    $mem = [int]((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1MB)
    if ($mem -lt 3800) { Add-Result WARN 'Memory' "$mem MiB" 'CommStat''s embedded web engine is memory-hungry; 4 GiB or more is comfortable on Windows.' }
    else { Add-Result OK 'Memory' "$mem MiB" }
}

function Test-Tools {
    $py = Find-BasePython
    if ($py) {
        $v = & $py -c "import sys; print('%d.%d.%d' % sys.version_info[:3])" 2>$null
        Add-Result OK 'Python' "$v ($py)"
    } elseif ($script:PF.Winget) {
        Add-Result WARN 'Python' '3.8 or newer not found' 'The installer will install Python 3.12 with winget (Python.Python.3.12).'
    } else {
        Add-Result FAIL 'Python' '3.8 or newer not found' 'Install Python 3.12 from python.org (or: winget install Python.Python.3.12).'
    }
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { Add-Result OK 'git' "$((& git.exe --version) -replace 'git version ', '')" }
    else { Add-Result OK 'git' 'not installed (not needed: CommStat is downloaded as a zip)' }
}

function Test-Network {
    if (-not $script:PF.Network) { Add-Result WARN 'Internet' 'skipped (-NoNetwork)' 'The installer downloads programs and CommStat.'; return }
    foreach ($h in @(
        @{ H = 'github.com'; P = 443; Why = 'CommStat is downloaded from here'; Must = $true },
        @{ H = 'codeload.github.com'; P = 443; Why = 'CommStat zip downloads'; Must = $true },
        @{ H = 'pypi.org'; P = 443; Why = 'CommStat''s Python packages'; Must = $true },
        @{ H = 'files.pythonhosted.org'; P = 443; Why = 'CommStat''s Python packages'; Must = $true },
        @{ H = 'files.js8call.com'; P = 80; Why = 'the JS8Call installer'; Must = $false },
        @{ H = 'www.w1hkj.org'; P = 443; Why = 'the FLDIGI/FLMSG/FLAMP installers'; Must = $false })) {
        if (Test-TcpReachable $h.H $h.P) { Add-Result OK "Host: $($h.H)" "reachable ($($h.Why))" }
        elseif ($h.Must) { Add-Result FAIL "Host: $($h.H)" "cannot reach port $($h.P)" 'Check your internet connection, proxy, or firewall.' }
        else { Add-Result WARN "Host: $($h.H)" "cannot reach port $($h.P)" "Needed for $($h.Why) unless it's already installed." }
    }
}

function Test-Programs($c) {
    $list = @(@{ N = 'js8call'; Id = 'JS8Call-improved.JS8Call-improved'; Cfg = $c.JS8CALL_EXE; Optional = $false })
    if ($script:PF.Fldigi) {
        $list += @{ N = 'fldigi'; Id = 'w1hkj.fldigi'; Cfg = $c.FLDIGI_EXE; Optional = $true }
        $list += @{ N = 'flmsg';  Id = 'w1hkj.flmsg';  Cfg = $c.FLMSG_EXE;  Optional = $true }
        $list += @{ N = 'flamp';  Id = 'w1hkj.flamp';  Cfg = $c.FLAMP_EXE;  Optional = $true }
    }
    foreach ($p in $list) {
        $exe = Find-Program $p.N $p.Cfg
        if ($exe) { Add-Result OK "program: $($p.N)" "already installed ($exe) - kept as it is" }
        elseif ($p.Cfg) { Add-Result FAIL "program: $($p.N)" "not found at $($p.Cfg)" "Fix $($p.N.ToUpper())_EXE in $($c.CONFIG_DIR)\config, or clear it to search automatically." }
        elseif ($script:PF.Winget) { Add-Result OK "program: $($p.N)" "not installed - will be installed with winget ($($p.Id))" }
        elseif ($p.Optional) { Add-Result WARN "program: $($p.N)" 'not installed' 'Needed only for the FLDIGI station. Install it from w1hkj.org, or use -NoFldigi.' }
        else { Add-Result FAIL "program: $($p.N)" 'not installed' 'Install JS8Call 3 from js8call.com (or: winget install JS8Call-improved.JS8Call-improved).' }
    }
}

function Test-Audio($c) {
    $svc = Get-Service Audiosrv -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') { Add-Result FAIL 'Audio service' 'Windows Audio isn''t running' 'Start the "Windows Audio" service, or restart Windows.'; return }
    Add-Result OK 'Audio service' 'Windows Audio is running'
    try { Initialize-Audio } catch { Add-Result FAIL 'Audio devices' "can't read the device list: $($_.Exception.Message)" ''; return }
    $cableHint = 'Install a virtual audio cable - VB-CABLE is free: https://vb-audio.com/Cable/ (run its setup as administrator, then restart Windows). Or set the device names in the config file.'
    $stations = @(@{ Tag = 'JS8Call'; Play = $c.JS8_PLAY_DEVICE; Rec = $c.JS8_REC_DEVICE; Tx = $c.JS8_TX_DEVICE; Level = 'FAIL'; Prefix = 'JS8' })
    $sameCable = ($c.FL_PLAY_DEVICE -eq $c.JS8_PLAY_DEVICE) -and ($c.FL_REC_DEVICE -eq $c.JS8_REC_DEVICE)
    if ($script:PF.Fldigi -and -not $sameCable) { $stations +=@{ Tag = 'FLDIGI'; Play = $c.FL_PLAY_DEVICE; Rec = $c.FL_REC_DEVICE; Tx = $c.FL_TX_DEVICE; Level = 'WARN'; Prefix = 'FL' } }
    foreach ($s in $stations) {
        $play = Find-AudioDevice $s.Play 'Render'; $rec = Find-AudioDevice $s.Rec 'Capture'
        if ($play -and $rec) { Add-Result OK "Cable ($($s.Tag))" "browser plays into '$($play.Name)'; decoder records '$($rec.Name)'" }
        else {
            $miss = @(); if (-not $play) { $miss += "playback device '$($s.Play)'" }; if (-not $rec) { $miss += "recording device '$($s.Rec)'" }
            Add-Result $s.Level "Cable ($($s.Tag))" "not found: $($miss -join ', ')" $cableHint
        }
        if ($s.Tx -ne $s.Play -and -not (Find-AudioDevice $s.Tx 'Render')) {
            Add-Result WARN "TX device ($($s.Tag))" "'$($s.Tx)' not found" "Set $($s.Prefix)_TX_DEVICE to a playback device that goes nowhere audible (blank = the cable)."
        }
    }
    $def = Get-DefaultAudioDevice 'Render'
    if ($def -and (($def.Name -like "$($c.JS8_PLAY_DEVICE)*") -or ($script:PF.Fldigi -and $def.Name -like "$($c.FL_PLAY_DEVICE)*"))) {
        Add-Result WARN 'Default speakers' "Windows' default playback device is '$($def.Name)'" 'Every program''s sound would go into the decoder (some cable installers do this). Set your real speakers as the default in Settings > System > Sound.'
    } elseif ($def) { Add-Result OK 'Default speakers' $def.Name }
    if ($script:PF.Fldigi -and $c.FL_PLAY_DEVICE -eq $c.JS8_PLAY_DEVICE) {
        Add-Result WARN 'Two stations' "both use '$($c.JS8_PLAY_DEVICE)'" 'Fine for one station at a time. To run both at once, add a second cable (e.g. VB-Audio Hi-Fi Cable or CABLE A+B) and set FL_PLAY_DEVICE / FL_REC_DEVICE in the config file.'
    }
}

function Test-Browser {
    $names = @()
    foreach ($root in 'HKLM:\SOFTWARE\Clients\StartMenuInternet', 'HKCU:\SOFTWARE\Clients\StartMenuInternet', 'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet') {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $n = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)'
            if (-not $n) { $n = $_.PSChildName }
            $names += $n
        }
    }
    $names = @($names | Where-Object { $_ -notmatch 'Internet Explorer' } | Sort-Object -Unique)
    $hint = 'Windows routes audio per program, not per tab: a browser used only for the WebSDR keeps your other browser''s sound on your speakers.'
    if ($names.Count -ge 2) { Add-Result OK 'Web browsers' ($names -join ', ') }
    elseif ($names.Count -eq 1) { Add-Result OK 'Web browser' $names[0] "Optional: install a second browser (e.g. Firefox). $hint" }
    else { Add-Result WARN 'Web browser' 'none found' 'You need a browser to play the WebSDR/KiwiSDR page.' }
}

function Test-Clock {
    if (-not $script:PF.Network) { Add-Result WARN 'Clock' 'not checked (-NoNetwork)' 'JS8 needs the clock accurate to about a second.'; return }
    $off = Get-ClockOffset
    if ($null -eq $off) { Add-Result WARN 'Clock' 'could not reach time.windows.com to compare' 'Make sure your clock is accurate; JS8 decodes on tight time slots.'; return }
    $txt = '{0:+0.00;-0.00} s from time.windows.com' -f $off
    if ([math]::Abs($off) -le 1.0) { Add-Result OK 'Clock' "$txt (JS8 needs about 1 s)" }
    else { Add-Result WARN 'Clock' $txt 'JS8 decodes on tight time slots. Settings > Time & language > Date & time > "Sync now" (Windows only syncs occasionally; a tool such as Meinberg NTP or BktTimeSync keeps it accurate).' }
}

function Test-Settings($c) {
    $bad = $false
    if (-not (Test-ProfileName $c.PROFILE)) { Add-Result FAIL 'Setting: PROFILE' "'$($c.PROFILE)' - use letters, digits and underscores only" "Edit $($c.CONFIG_DIR)\config."; $bad = $true }
    foreach ($k in 'TCP_PORT', 'UDP_PORT') { if (-not (Test-Port $c[$k])) { Add-Result FAIL "Setting: $k" "'$($c[$k])' is not a port between 1024 and 65535" ''; $bad = $true } }
    foreach ($k in 'JS8_PLAY_DEVICE', 'JS8_REC_DEVICE', 'JS8_TX_DEVICE') { if (-not (Test-DeviceName $c[$k])) { Add-Result FAIL "Setting: $k" "'$($c[$k])' isn't a usable device name" ''; $bad = $true } }
    if (-not $bad) { Add-Result OK 'Settings' "profile '$($c.PROFILE)', ports $($c.TCP_PORT)/$($c.UDP_PORT)" }
    if (-not $script:PF.Fldigi) { return }
    $fbad = $false
    foreach ($k in 'FL_XMLRPC_PORT', 'FL_ARQ_PORT', 'FL_KISS_IO_PORT', 'FL_KISS_OUT_PORT') { if (-not (Test-Port $c[$k])) { Add-Result FAIL "Setting: $k" "'$($c[$k])' is not a port between 1024 and 65535" ''; $fbad = $true } }
    foreach ($k in 'FL_PLAY_DEVICE', 'FL_REC_DEVICE', 'FL_TX_DEVICE') { if (-not (Test-DeviceName $c[$k])) { Add-Result FAIL "Setting: $k" "'$($c[$k])' isn't a usable device name" ''; $fbad = $true } }
    if (-not $fbad) { Add-Result OK 'FLDIGI settings' "ports $($c.FL_XMLRPC_PORT)/$($c.FL_ARQ_PORT), folders $($c.FLDIGI_DIR), $($c.NBEMS_DIR)" }
}

function Test-Existing($c) {
    $ours = @(Get-Js8Process $c).Count -gt 0
    if ($ours) { Add-Result WARN 'JS8Call profile' "'$($c.PROFILE)' is running right now" 'Close it before installing; JS8Call rewrites its settings when it exits.' }
    if (Test-PortInUse $c.TCP_PORT) {
        if ($ours) { Add-Result OK "TCP port $($c.TCP_PORT)" "in use by this install's own JS8Call" }
        else { Add-Result FAIL "TCP port $($c.TCP_PORT)" 'already in use by something else' "Choose another port: set TCP_PORT in $($c.CONFIG_DIR)\config (or WEBSDR_JS8_TCP_PORT)." }
    } else { Add-Result OK "TCP port $($c.TCP_PORT)" 'free' }
    if ($script:PF.Fldigi) {
        $flOurs = @(Get-FldigiProcess $c).Count -gt 0
        foreach ($p in $c.FL_XMLRPC_PORT, $c.FL_ARQ_PORT) {
            if (-not (Test-PortInUse $p)) { Add-Result OK "TCP port $p" 'free (FLDIGI station)' }
            elseif ($flOurs) { Add-Result OK "TCP port $p" "in use by this install's own FLDIGI" }
            else { Add-Result WARN "TCP port $p" 'already in use by something else' "The FLDIGI station needs it. Set FL_XMLRPC_PORT / FL_ARQ_PORT in $($c.CONFIG_DIR)\config." }
        }
        if (Test-Path -LiteralPath (Join-Path $c.FLDIGI_DIR 'fldigi_def.xml')) { Add-Result OK 'FLDIGI settings' "$($c.FLDIGI_DIR) exists - it will be kept (receive-only settings are re-applied at each start)" }
    }
    if (Test-Path -LiteralPath $c.JS8_INI) { Add-Result OK 'JS8Call profile' "$($c.JS8_INI) exists - it will be kept, not overwritten" }
    if (Test-Path -LiteralPath (Join-Path $c.COMMSTAT_DIR 'commstat.py')) { Add-Result OK 'CommStat' "existing install at $($c.COMMSTAT_DIR) - it will be reused, not overwritten" }
}

# --------------------------------------------------------------------- main
function Invoke-Preflight {
    $script:N_OK = 0; $script:N_WARN = 0; $script:N_FAIL = 0
    $c = Get-WebSdrConfig
    Write-Host "WebSDR-Digital-Receive-Only $WEBSDR_JS8_VERSION - prerequisite check" -ForegroundColor White
    Write-Host "Read-only: nothing is installed or changed.`n" -ForegroundColor DarkGray
    Test-OS; Test-Arch; Test-User; Test-Winget; Test-Resources; Test-Tools
    Test-Network; Test-Programs $c; Test-Audio $c; Test-Browser; Test-Clock
    Test-Settings $c; Test-Existing $c
    Write-Host ("`n  {0} passed, {1} warning(s), {2} failure(s)" -f $script:N_OK, $script:N_WARN, $script:N_FAIL)
    if ($script:N_FAIL -gt 0) {
        Write-Host "`nNot ready: fix the items marked FAIL above, then run .\preflight.cmd again." -ForegroundColor Red
        return $false
    }
    if ($script:N_WARN -gt 0) { Write-Host "`nReady to install. Warnings won't stop the install, but are worth a look." }
    else { Write-Host "`nAll clear - ready to install." }
    return $true
}

# Run directly (not dot-sourced by install.ps1): do the check and exit with its result.
if ($MyInvocation.InvocationName -ne '.') {
    if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
    if (Invoke-Preflight) { exit 0 } else { exit 1 }
}
