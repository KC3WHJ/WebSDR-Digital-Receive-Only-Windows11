<#
Installer for WebSDR-Digital-Receive-Only (Windows): receive-only JS8Call + CommStat and
FLDIGI + FLMSG + FLAMP stations fed by a web SDR / KiwiSDR audio stream (no radio,
no transmitting).

  .\install.cmd                   check prerequisites, then install
  .\install.cmd -Check            prerequisite check only (changes nothing)

Options:
  -Callsign CALL -Grid GRID -State ST   skip the questions (state is optional)
  -Yes                            don't stop to ask; accept warnings and winget's agreements
  -SkipWinget                     don't install programs (you've done it already)
  -SkipCommStatDeps               don't run CommStat's own dependency installer
  -NoFldigi                       leave out the FLDIGI + FLMSG + FLAMP station
  -NoDesktopIcons                 don't create Desktop shortcuts
  -NoPath                         don't add the launchers' folder to your PATH
  -NoNetwork                      skip the internet checks (testing only)
  -Help                           this text

Order of operations: (1) prerequisite check - if anything is marked FAIL the installer
stops here and has changed nothing; (2) questions; (3) programs; (4) CommStat;
(5) configuration; (6) launchers; (7) verification.

Needs a virtual audio cable driver (VB-CABLE: https://vb-audio.com/Cable/), which
you install yourself - it needs administrator rights and a restart.
#>
[CmdletBinding()]
param(
    [switch]$Check, [switch]$Yes, [switch]$SkipWinget, [switch]$SkipCommStatDeps, [switch]$NoFldigi,
    [switch]$NoDesktopIcons, [switch]$NoPath, [switch]$NoNetwork,
    [string]$Callsign = '', [string]$Grid = '', [string]$State = '', [switch]$Help
)
$HERE = $PSScriptRoot
if ($Help) { . (Join-Path $HERE 'lib\Common.ps1'); Show-ScriptHelp $PSCommandPath; exit 0 }

# preflight.ps1 only defines its checks when dot-sourced; it loads lib\Common.ps1 itself.
. (Join-Path $HERE 'preflight.ps1') -NoNetwork:$NoNetwork -NoFldigi:$NoFldigi -SkipWinget:$SkipWinget

$WITH_FLDIGI = -not $NoFldigi
$COMMSTAT_ZIP = if ($env:WEBSDR_JS8_COMMSTAT_ZIP) { $env:WEBSDR_JS8_COMMSTAT_ZIP } else { 'https://codeload.github.com/mgochoa57/CommStat/zip/refs/heads/main' }
$COMMSTAT_GIT = if ($env:WEBSDR_JS8_COMMSTAT_URL) { $env:WEBSDR_JS8_COMMSTAT_URL } else { 'https://github.com/mgochoa57/CommStat.git' }
$RIG_NAME = 'WebSDR'    # the connector's name inside CommStat
$PACKAGES = @(@{ N = 'js8call'; Id = 'JS8Call-improved.JS8Call-improved'; Key = 'JS8CALL_EXE' })
$FL_PACKAGES = @(@{ N = 'fldigi'; Id = 'w1hkj.fldigi'; Key = 'FLDIGI_EXE' }, @{ N = 'flmsg'; Id = 'w1hkj.flmsg'; Key = 'FLMSG_EXE' }, @{ N = 'flamp'; Id = 'w1hkj.flamp'; Key = 'FLAMP_EXE' })

# ------------------------------------------------------ 1. prerequisites
if (-not (Invoke-Preflight)) { Write-Host "`nNothing was installed or changed."; exit 1 }
if ($Check) { exit 0 }
if ($script:N_WARN -gt 0 -and -not $Yes) {
    $ans = Read-Host "`nContinue despite the warnings above? [Y/n]"
    if ($ans -and $ans -notmatch '^[Yy]') { Write-Host 'Stopped. Nothing was installed or changed.'; exit 1 }
}

$c = Get-WebSdrConfig

# -------------------------------------------------------------- 2. settings
Write-Step 'Your details'
Write-Info @'
CommStat and JS8Call need a callsign and grid square to start. If you're only
listening you can use any short ID (for example a tactical call, or N0CALL);
use your real callsign if you have one. The grid is where YOU are, not the SDR.
'@

function Read-Setting([string]$Current, [string]$Prompt, [scriptblock]$Valid, [string]$Err) {
    $v = $Current
    while ($true) {
        if (-not $v) {
            if (-not (Test-Interactive)) { Fail "$Prompt is required. Pass it as a parameter (see -Help) when running non-interactively." }
            $v = Read-Host $Prompt
        }
        if (& $Valid $v) { return $v }
        Write-Host "  $Err" -ForegroundColor Yellow
        if (-not (Test-Interactive)) { exit 1 }
        $v = ''
    }
}
if ($Callsign) { $c.CALLSIGN = $Callsign }
if ($Grid)     { $c.GRID = $Grid }
if ($State)    { $c.STATE = $State }
$c.CALLSIGN = Read-Setting $c.CALLSIGN 'Callsign or ID' { param($v) Test-Callsign $v } "Use 3-12 letters/digits (a '/' is allowed), e.g. W1AW or N0CALL."
$c.GRID     = Read-Setting $c.GRID 'Your 4- or 6-character grid' { param($v) Test-Grid $v } 'A grid square looks like FN31 or FN31pr (letters A-R, then two digits).'
if (-not $State -and -not $c.STATE -and (Test-Interactive)) { $c.STATE = Read-Host 'Your US state code, e.g. PA (blank if not applicable)' }
if (-not (Test-State $c.STATE)) { Fail 'State must be two letters (or empty).' }
$c.CALLSIGN = $c.CALLSIGN.ToUpper(); $c.STATE = $c.STATE.ToUpper(); $c.GRID = Format-Grid $c.GRID
Write-Info "Using: $($c.CALLSIGN)  $($c.GRID)  $(if ($c.STATE) { $c.STATE } else { '(no state)' })"

# -------------------------------------------------------------- 3. programs
function Invoke-Winget([string]$Id, [string[]]$Extra = @()) {
    $a = @('install', '--id', $Id, '--exact', '--source', 'winget') + $Extra
    if ($Yes) { $a += @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') }
    & winget.exe @a | Out-Host     # show winget's messages; only the exit code is returned
    return $LASTEXITCODE
}

$wanted = $PACKAGES; if ($WITH_FLDIGI) { $wanted += $FL_PACKAGES }
if ($SkipWinget) {
    Write-Step 'Programs'; Write-Info 'Skipped (-SkipWinget).'
} else {
    Write-Step 'Installing programs with winget (Windows may ask for administrator approval)'
    # Keep programs that are already installed, whatever version: replacing someone's own
    # JS8Call or FLDIGI could disturb their normal radio setup.
    foreach ($p in $wanted) {
        $exe = Find-Program $p.N $c[$p.Key]
        if ($exe) { Write-Info "$($p.N) is already installed ($exe) - keeping it as it is."; continue }
        Write-Info "Installing $($p.N) ($($p.Id))..."
        if ((Invoke-Winget $p.Id) -ne 0) { Write-Warn "winget couldn't install $($p.Id) - see its message above." }
    }
    if (-not (Find-BasePython)) {
        Write-Info 'Installing Python 3.12 (Python.Python.3.12) for CommStat...'
        if ((Invoke-Winget 'Python.Python.3.12' @('--scope', 'user')) -ne 0) {
            if ((Invoke-Winget 'Python.Python.3.12') -ne 0) { Write-Warn "winget couldn't install Python - see its message above." }
        }
    }
}
$basePython = Find-BasePython
if (-not $basePython) { Fail 'Python 3.8 or newer is still not available. Install Python 3.12 from python.org, then run the installer again.' }

# -------------------------------------------------------------- 4. CommStat
Write-Step 'CommStat'
$csDir = $c.COMMSTAT_DIR
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $csDir) | Out-Null
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath (Join-Path $csDir '.git')) {
    # CommStat updates itself in place (its server pushes program updates that rewrite its
    # files), so its checkout is normally "dirty" after first use, and a plain pull would
    # abort. Pull only when clean; otherwise leave updating to the app itself.
    if (-not $git) { Write-Info 'CommStat is a git checkout but git isn''t installed - keeping it as it is.' }
    elseif (-not (& git.exe -C $csDir -c core.fileMode=false status --porcelain --untracked-files=no)) {
        & git.exe -C $csDir -c core.fileMode=false pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Warn "couldn't update CommStat from GitHub - keeping the installed copy." }
    } else { Write-Info 'CommStat has updated itself in place (its own update channel) - keeping it as it is.' }
} elseif (Test-Path -LiteralPath $csDir) {
    Write-Info "$csDir already exists - using it as it is."
} elseif ($git) {
    & git.exe clone --quiet $COMMSTAT_GIT $csDir
    if ($LASTEXITCODE -ne 0) { Fail "couldn't clone CommStat from $COMMSTAT_GIT." }
    Write-Info "Cloned CommStat to $csDir."
} else {
    $tmp = Join-Path $c.DATA_DIR 'download'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -Recurse -Force -LiteralPath $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'CommStat.zip'
    Write-Info "Downloading CommStat from GitHub..."
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $COMMSTAT_ZIP -OutFile $zip -ErrorAction Stop
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force -ErrorAction Stop
        $inner = Get-ChildItem -Directory (Join-Path $tmp 'x') | Select-Object -First 1
        if (-not $inner) { throw 'the download was empty' }
        Move-Item -LiteralPath $inner.FullName -Destination $csDir -ErrorAction Stop
    } catch { Fail "couldn't download CommStat from ${COMMSTAT_ZIP}: $($_.Exception.Message)" }
    Remove-Item -Recurse -Force -LiteralPath $tmp
    Write-Info "Downloaded CommStat to $csDir (it keeps itself up to date from its own server)."
}
if (-not (Test-Path -LiteralPath (Join-Path $csDir 'commstat.py'))) { Fail "CommStat's files aren't at $csDir - something went wrong." }

# CommStat gets a Python environment of its own, so its packages (PyQt5, Qt WebEngine, ...)
# can't clash with anything else installed in your Python.
$venv = Join-Path $c.DATA_DIR 'venv'
$c.PYTHON = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $c.PYTHON)) {
    Write-Info "Creating CommStat's Python environment ($venv) from $basePython..."
    if ((Invoke-Native $basePython @('-m', 'venv', $venv)) -ne 0) { Fail "couldn't create a Python environment at $venv." }
}
if ($SkipCommStatDeps) {
    Write-Info "Skipped CommStat's own dependency installer (-SkipCommStatDeps)."
} elseif (Test-Path -LiteralPath (Join-Path $csDir 'install.py')) {
    Write-Info "Running CommStat's own installer (installs PyQt5, Qt WebEngine and its other Python packages)..."
    [void](Invoke-Native $c.PYTHON @('-m', 'pip', 'install', '--quiet', '--upgrade', 'pip') $csDir)
    if ((Invoke-Native $c.PYTHON @('install.py') $csDir) -ne 0) { Fail "CommStat's installer failed - see its message above." }
} else {
    Write-Warn "CommStat has no install.py here - install its dependencies by hand (see its README)."
}

# --------------------------------------------------------- 5. configuration
Write-Step 'Configuring for receive-only use'
$seed = @((Join-Path $HERE 'share\seed_commstat.py'), $csDir, $c.CALLSIGN, $c.GRID, $c.STATE, $RIG_NAME, $c.TCP_PORT)
if ((Invoke-Native $c.PYTHON $seed) -ne 0) { Fail "couldn't configure CommStat (see above)." }

if (Test-Path -LiteralPath $c.JS8_INI) {
    Write-Info "JS8Call profile '$($c.PROFILE)' already exists - keeping it."
    if ((Get-IniValue $c.JS8_INI 'Rig') -ne 'None') {
        Write-Warn "That profile is NOT receive-only (Rig is '$(Get-IniValue $c.JS8_INI 'Rig')'), so websdr-js8-start will refuse to use it. Choose another PROFILE in $($c.CONFIG_DIR)\config, or remove $($c.JS8_INI)."
    }
} else {
    # Use each device's full Windows name where the cable is present.
    $rec = Find-AudioDevice $c.JS8_REC_DEVICE 'Capture'; $tx = Find-AudioDevice $c.JS8_TX_DEVICE 'Render'
    $tpl = [IO.File]::ReadAllText((Join-Path $HERE 'share\JS8Call-profile.ini.template'))
    $tpl = $tpl.Replace('@CALLSIGN@', $c.CALLSIGN).Replace('@GRID@', $c.GRID).Replace('@TCP_PORT@', $c.TCP_PORT).Replace('@UDP_PORT@', $c.UDP_PORT)
    $tpl = $tpl.Replace('@SAVE_DIR@', ((Join-Path $c.JS8_HOME 'save') -replace '\\', '/'))
    $tpl = $tpl.Replace('@REC_DEVICE@', $(if ($rec) { $rec.Name } else { $c.JS8_REC_DEVICE }))
    $tpl = $tpl.Replace('@TX_DEVICE@', $(if ($tx) { $tx.Name } else { $c.JS8_TX_DEVICE }))
    Write-TextFile $c.JS8_INI ($tpl -replace "`r?`n", "`r`n")
    Write-Info "Wrote JS8Call profile: $($c.JS8_INI)  (no rig control, spotting off)"
}
Save-WebSdrConfig $c
Write-Info "Saved settings to $($c.CONFIG_DIR)\config"

# ------------------------------------------------------------ 6. launchers
Write-Step 'Installing launchers'
foreach ($d in 'bin', 'lib', 'share') {
    $dst = Join-Path $c.APP_DIR $d
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Force -Path (Join-Path $HERE "$d\*") -Destination $dst
}
Get-ChildItem -Recurse -File $c.APP_DIR | Unblock-File   # downloaded copies carry the "from the internet" mark
New-Item -ItemType Directory -Force -Path $c.BIN_DIR | Out-Null
$commands = @('websdr-js8-start', 'websdr-js8-stop', 'websdr-audio-check')
if ($WITH_FLDIGI) { $commands += @('websdr-fldigi-start', 'websdr-fldigi-stop') }
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach ($cmd in $commands) {
    $script = Join-Path $c.APP_DIR "bin\$cmd.ps1"
    Write-TextFile (Join-Path $c.BIN_DIR "$cmd.cmd") "@echo off`r`n`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$script`" %*`r`n"
}
Write-Info "Installed $($commands -join ', ') in $($c.BIN_DIR)"

if ($NoPath) {
    Write-Info "Not added to PATH (-NoPath). Run them as $($c.BIN_DIR)\<name>, or from the Start Menu."
} else {
    $key = Get-Item 'HKCU:\Environment'
    $userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    if (($userPath -split ';') -notcontains $c.BIN_DIR) {
        $new = (@($userPath -split ';' | Where-Object { $_ }) + $c.BIN_DIR) -join ';'
        Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $new -Type ExpandString
        Send-EnvironmentChanged
        Write-Info "Added $($c.BIN_DIR) to your PATH (takes effect in newly opened windows)."
    }
}

New-StationShortcuts $c $WITH_FLDIGI (-not $NoDesktopIcons)

# ------------------------------------------------------------ 7. verify
Write-Step 'Checking the result'
$bad = $false
function Confirm-Item([bool]$Ok, [string]$Good, [string]$BadText) {
    if ($Ok) { Write-Info "  ok  $Good" } else { Write-Warn $BadText; $script:bad = $true }
}
foreach ($p in $wanted) { $exe = Find-Program $p.N $c[$p.Key]; Confirm-Item ([bool]$exe) "$($p.N): $exe" "$($p.N) not found - install it (winget install $($p.Id)) and run the installer again." }
$qtOk = (Test-Path -LiteralPath $c.PYTHON) -and ((Invoke-Native $c.PYTHON @('-c', 'import PyQt5.QtWebEngineWidgets, PyQt5.QtMultimedia')) -eq 0)
Confirm-Item $qtOk 'Qt WebEngine / Multimedia available to CommStat''s Python' "CommStat's Qt WebEngine Python modules aren't importable - re-run without -SkipCommStatDeps."
Confirm-Item (Test-Path -LiteralPath $c.JS8_INI) 'JS8Call profile' 'JS8Call profile missing'
Confirm-Item (Test-Path -LiteralPath (Join-Path $csDir 'traffic.db3')) 'CommStat database' 'CommStat database missing'
Confirm-Item (Test-Path -LiteralPath (Join-Path $c.BIN_DIR 'websdr-js8-start.cmd')) 'launchers' 'launchers missing'
$cable = (Find-AudioDevice $c.JS8_PLAY_DEVICE 'Render') -and (Find-AudioDevice $c.JS8_REC_DEVICE 'Capture')
Confirm-Item $cable "virtual audio cable ($($c.JS8_PLAY_DEVICE) / $($c.JS8_REC_DEVICE))" 'virtual audio cable not found - install VB-CABLE (https://vb-audio.com/Cable/) and restart Windows.'

Write-Host ''
if (-not $bad) { Write-Host 'Installed.' -ForegroundColor Green }
else { Write-Host 'Installed with problems - see the warnings above.' -ForegroundColor Yellow }
Write-Info @"

Next:
  1. Run  websdr-js8-start   (or use "Start WebSDR JS8Call + CommStat" in the Start Menu)
  2. Open a web SDR / KiwiSDR in your browser, tune it to a JS8 frequency in USB mode
     (e.g. 7.078 MHz), and play its audio.
  3. When asked, set that browser's output to '$($c.JS8_PLAY_DEVICE)' in the Volume
     mixer page that opens. JS8Call starts decoding; CommStat connects to it.
  4. When finished:  websdr-js8-stop
"@
if ($WITH_FLDIGI) { Write-Info @"

FLDIGI + FLMSG + FLAMP works the same way:
  websdr-fldigi-start / websdr-fldigi-stop  (or the "WebSDR FLDIGI" shortcuts)
  Its settings are created on first start - from a copy of your fldigi.files if you have one.
"@ }
Write-Info "`nSee docs\USAGE.md for details. To remove everything: .\uninstall.cmd"
