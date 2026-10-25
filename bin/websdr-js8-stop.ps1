<#
Stop the receive-only JS8Call + CommStat station. Only touches things belonging to this
install (matched by its own JS8Call profile name and CommStat folder), never a normal
JS8Call or CommStat you may run separately.
#>
param([switch]$Pause, [switch]$Help)
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
$global:WEBSDR_PAUSE = [bool]$Pause
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig

Stop-StationProcess 'CommStat' { Get-CommStatProcess $c }
Stop-StationProcess "JS8Call (profile: $($c.PROFILE))" { Get-Js8Process $c }

$play = $null
try { $play = Find-AudioDevice $c.JS8_PLAY_DEVICE 'Render' } catch { }
Show-RoutingReminder $play
Write-Info ''
Write-Info 'Done.'
Exit-Script 0
