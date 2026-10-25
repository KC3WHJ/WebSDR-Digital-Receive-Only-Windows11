<#
Show the audio devices, which ones the stations use, and which programs are playing into
each virtual cable right now. Read-only: it changes nothing.

  websdr-audio-check
#>
param([switch]$Pause, [switch]$Help)
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
$global:WEBSDR_PAUSE = [bool]$Pause
if ($Help) { Show-ScriptHelp $PSCommandPath; exit 0 }
$c = Get-WebSdrConfig
Initialize-Audio

$defPlay = Get-DefaultAudioDevice 'Render'; $defRec = Get-DefaultAudioDevice 'Capture'
Write-Step 'Playback devices'
foreach ($d in [WebSdrAudio.Audio]::GetEndpoints(0)) { Write-Info ("  {0}{1}" -f $d.Name, $(if ($defPlay -and $d.Id -eq $defPlay.Id) { '   (Windows default)' } else { '' })) }
Write-Step 'Recording devices'
foreach ($d in [WebSdrAudio.Audio]::GetEndpoints(1)) { Write-Info ("  {0}{1}" -f $d.Name, $(if ($defRec -and $d.Id -eq $defRec.Id) { '   (Windows default)' } else { '' })) }

foreach ($s in @(@{ Tag = 'JS8Call station'; Play = $c.JS8_PLAY_DEVICE; Rec = $c.JS8_REC_DEVICE },
                 @{ Tag = 'FLDIGI station';  Play = $c.FL_PLAY_DEVICE;  Rec = $c.FL_REC_DEVICE })) {
    Write-Step $s.Tag
    $play = Find-AudioDevice $s.Play 'Render'; $rec = Find-AudioDevice $s.Rec 'Capture'
    Write-Info ("  browser plays into : {0}" -f $(if ($play) { $play.Name } else { "NOT FOUND ('$($s.Play)')" }))
    Write-Info ("  decoder records    : {0}" -f $(if ($rec) { $rec.Name } else { "NOT FOUND ('$($s.Rec)')" }))
    if ($play) {
        $who = @(Get-AudioPlayers $play)
        if ($who.Count -eq 0) { Write-Info '  playing into it    : nothing' }
        foreach ($w in $who) { Write-Info ("  playing into it    : {0} (pid {1}){2}" -f $w.ProcessName, $w.ProcessId, $(if ($w.Active) { ' - playing now' } else { ' - set to it, silent' })) }
    }
}
Exit-Script 0
