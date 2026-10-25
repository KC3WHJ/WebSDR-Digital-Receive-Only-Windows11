<#
Stop the receive-only FLDIGI + FLMSG + FLAMP station. Only touches this station's own
copies (matched by their settings folders), never a normal FLDIGI, FLMSG or FLAMP you
run with a radio.
#>
param([switch]$Pause, [switch]$Help)
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
$global:WEBSDR_PAUSE = [bool]$Pause
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig

# FLAMP and FLMSG first: FLAMP can hang on close once its FLDIGI is gone.
Stop-StationProcess 'FLAMP' { Get-FlampProcess $c }
Stop-StationProcess 'FLMSG' { Get-FlmsgProcess $c }

Write-Step 'Stopping FLDIGI'
$find = { Get-FldigiProcess $c }
if (@(& $find).Count -eq 0) {
    Write-Info 'Not running.'
} else {
    # Ask FLDIGI to close itself so it saves its settings (being killed makes it exit
    # without saving). 7 = save options, log and macros.
    $body = '<?xml version="1.0"?><methodCall><methodName>fldigi.terminate</methodName><params><param><value><i4>7</i4></value></param></params></methodCall>'
    try { [void](Invoke-WebRequest -UseBasicParsing -Method Post -Uri "http://127.0.0.1:$($c.FL_XMLRPC_PORT)/RPC2" -Body $body -ContentType 'text/xml' -TimeoutSec 5) } catch { }
    if (Wait-Gone $find 10) {
        Write-Info 'Stopped.'
    } else {
        foreach ($p in @(& $find)) { & taskkill.exe /T /F /PID $p.ProcessId 2>$null | Out-Null }
        [void](Wait-Gone $find 5)
        Write-Info 'Stopped (forced, without saving its settings).'
    }
}

$play = $null
try { $play = Find-AudioDevice $c.FL_PLAY_DEVICE 'Render' } catch { }
Show-RoutingReminder $play
Write-Info ''
Write-Info 'Done.'
Exit-Script 0
