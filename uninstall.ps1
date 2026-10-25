<#
Remove WebSDR-Digital-Receive-Only (Windows).

  .\uninstall.cmd              remove the launchers, shortcuts and settings; ASK before
                               deleting the JS8Call profile, the CommStat folder and the
                               FLDIGI/FLMSG/FLAMP settings folders
  .\uninstall.cmd -Purge       remove those too, without asking
  .\uninstall.cmd -KeepData    never remove them
  -Yes                         answer yes to the confirmations

It does NOT uninstall programs (JS8Call, FLDIGI, FLMSG, FLAMP, Python, VB-CABLE) - other
software may use them. To remove those: Settings > Apps > Installed apps, or winget uninstall.
#>
param([switch]$Purge, [switch]$KeepData, [switch]$Yes, [switch]$Help)
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig

function Confirm-Delete([string]$Question) {
    if ($Yes) { return $true }
    if (-not (Test-Interactive)) { return $false }
    return ((Read-Host "$Question [y/N]") -match '^[Yy]')
}
function Remove-Path([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -Recurse -Force -LiteralPath $Path; Write-Info "removed $Path" }
}

Write-Step 'Stopping anything that is running'
foreach ($s in 'websdr-js8-stop', 'websdr-fldigi-stop') {
    $p = Join-Path $PSScriptRoot "bin\$s.ps1"
    if (Test-Path -LiteralPath $p) { & $p }
}

Write-Step 'Removing launchers, shortcuts and settings'
foreach ($n in $SHORTCUT_NAMES) { Remove-Path (Join-Path $c.DESKTOP_DIR "$n.lnk") }
Remove-Path $c.MENU_DIR
$key = Get-Item 'HKCU:\Environment'
$userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
if (($userPath -split ';') -contains $c.BIN_DIR) {
    $new = ($userPath -split ';' | Where-Object { $_ -and $_ -ne $c.BIN_DIR }) -join ';'
    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $new -Type ExpandString
    Send-EnvironmentChanged
    Write-Info "removed $($c.BIN_DIR) from your PATH"
}
foreach ($p in 'bin', 'app', 'venv', 'download', 'fldigi', 'commstat.log', 'commstat.log.err') { Remove-Path (Join-Path $c.DATA_DIR $p) }
Remove-Path $c.CONFIG_DIR

if ($KeepData) {
    Write-Info ''; Write-Info 'Kept your JS8Call profile, CommStat folder and FLDIGI/FLMSG/FLAMP settings (-KeepData).'
} else {
    Write-Step 'Data'
    if ((Test-Path -LiteralPath $c.JS8_HOME) -and ($Purge -or (Confirm-Delete "Delete the JS8Call profile '$($c.PROFILE)' (settings and received-message history)?"))) { Remove-Path $c.JS8_HOME }
    if ((Test-Path -LiteralPath $c.COMMSTAT_DIR) -and ($Purge -or (Confirm-Delete "Delete the CommStat folder $($c.COMMSTAT_DIR) (its database and settings)?"))) { Remove-Path $c.COMMSTAT_DIR }
    if ((Test-Path -LiteralPath $c.FLDIGI_DIR) -and ($Purge -or (Confirm-Delete "Delete the WebSDR FLDIGI settings $($c.FLDIGI_DIR)?"))) { Remove-Path $c.FLDIGI_DIR }
    if ((Test-Path -LiteralPath $c.NBEMS_DIR) -and ($Purge -or (Confirm-Delete "Delete the WebSDR FLMSG/FLAMP folder $($c.NBEMS_DIR) (settings and received messages)?"))) { Remove-Path $c.NBEMS_DIR }
    if ((Test-Path -LiteralPath $c.DATA_DIR) -and -not (Get-ChildItem -Force -LiteralPath $c.DATA_DIR)) { Remove-Item -LiteralPath $c.DATA_DIR }
}

Write-Info ''
Write-Info 'Done. Installed programs (JS8Call, FLDIGI, FLMSG, FLAMP, Python, VB-CABLE) were left alone - remove them from Settings > Apps if you want.'
