# How it works

## The audio path

```
 browser (WebSDR / KiwiSDR audio)
        |  Output device set to "CABLE Input" in Settings > Sound > Volume mixer
        v
 virtual audio cable (VB-CABLE)      <- a driver: what plays into "CABLE Input" comes out of
        |                               the recording device "CABLE Output". Nothing is heard.
        v
      JS8Call  (its own profile: js8call -r WebSDR, records "CABLE Output")
        |  TCP API on 127.0.0.1:2443  (one client allowed by JS8Call)
        v
      CommStat  (one connector, "WebSDR", to that port)

 JS8Call's *output* -> "CABLE Input" too: transmit audio stays inside the PC
```

Linux has "null sinks" a script can create and remove; Windows has no built-in equivalent, so
a virtual audio cable driver stands in. It is installed once and simply stays there.

## Routing: why it's a Settings page and not a command

PipeWire lets a script move one stream (one browser tab). Windows keeps a per-*program*
output-device choice (*Volume mixer > Apps*), and the only way programs like EarTrumpet change
it is an undocumented internal interface that changes between Windows builds. Rather than
depend on that, the launcher:

1. opens `ms-settings:apps-volume` and tells you exactly which device to pick, then
2. **verifies** the result through the documented Core Audio API
   (`IAudioSessionManager2`, in `lib\AudioHelper.cs`): it lists the programs with an active
   audio session on the cable, ignoring the decoders themselves. Only when something is
   actually playing into the cable does it say the audio is routed.

`AudioHelper.cs` only reads; it never changes an audio setting. The same check runs when a
station stops: if your browser is still set to the cable, you're told and the page is opened
so you can set it back to Default.

Because the choice is per program, the Linux version's stray-stream watcher has no Windows
counterpart: every tab of the routed browser goes to the cable, which is why a second browser
for the WebSDR is recommended.

## Why a separate JS8Call profile

`js8call -r WebSDR` uses its own settings file
(`%LOCALAPPDATA%\JS8Call - WebSDR\JS8Call - WebSDR.ini`), data folder and API port. A normal
JS8Call configured for a real radio is unaffected and vice versa, and both can run at once.

## The receive-only guard

The profile is written with no rig control. Because a profile can be edited later from inside
JS8Call (*Settings > Radio*), `websdr-js8-start` re-reads it on every start and refuses to
launch if `Rig` isn't `None`, if a CAT serial port, CAT network port or PTT port is set, or if
`PSKReporter` / `SpotToAPRS` isn't explicitly `false`. It tells you exactly what to fix. This is
a check on this station's own configuration: JS8Call and CommStat are unmodified.

## Startup order and detaching

CommStat connects to JS8Call once at startup and disables the connector after repeated
failures, so the launcher starts JS8Call, **waits for its API port**, and only then starts
CommStat.

Programs are started with `Start-Process`. JS8Call, FLDIGI, FLMSG and FLAMP are windowed
programs with no console, and CommStat runs under `pythonw.exe` (no console either), so none of
them is attached to the launcher's window: closing that window can't close them.

## The installer

1. **Prerequisite check** (read-only). A FAIL stops here with nothing changed.
2. Your callsign, grid and state (parameters or prompts; validated before anything is installed).
3. `winget` installs JS8Call, FLDIGI, FLMSG, FLAMP and Python - each only if it isn't already
   installed, whatever its version (replacing your own copy could disturb a radio setup).
4. CommStat: downloaded from GitHub (or `git clone`d if you have git; an existing clean git
   checkout is pulled, a self-updated one is left alone). It gets its own Python environment
   (`venv`), and CommStat's own `install.py` installs PyQt5, Qt WebEngine and its other packages
   into it.
5. `share\seed_commstat.py` creates CommStat's database from its own template, fills in your
   details **only where still blank**, and adds the single `WebSDR` connector through
   CommStat's own `ConnectorManager`, with auto-connect on and RF Ack off.
6. The JS8Call profile is written from `share\JS8Call-profile.ini.template` **only if it
   doesn't exist**, with the cable's full Windows device names.
7. Launchers (`.cmd` files on your PATH), Start Menu and Desktop shortcuts, then the result
   is verified.

Every step is idempotent: re-running keeps existing profiles, databases and connectors.

## Layout

```
install.cmd  install.ps1        installer (install.cmd runs it without changing execution policy)
preflight.cmd  preflight.ps1    prerequisite check
uninstall.cmd  uninstall.ps1
lib\Common.ps1                  settings, validation, process and audio helpers
lib\AudioHelper.cs              read-only Core Audio access (devices, who is playing where)
lib\Fldigi.ps1                  FLDIGI/FLMSG/FLAMP settings and the FLDIGI guard
bin\websdr-js8-start.ps1        JS8Call + CommStat launcher
bin\websdr-js8-stop.ps1         its stopper
bin\websdr-fldigi-start.ps1     FLDIGI + FLMSG + FLAMP launcher
bin\websdr-fldigi-stop.ps1      its stopper
bin\websdr-audio-check.ps1      read-only audio report
share\JS8Call-profile.ini.template
share\seed_commstat.py          CommStat first-run configuration (same as the Linux version)
tests\run-tests.ps1             114 checks
```

## The FLDIGI station

```
 browser (WebSDR / KiwiSDR audio) -> cable -> FLDIGI
        (fldigi --config-dir .../fldigi-websdr.files/ --flmsg-dir .../NBEMS-websdr.files/,
         XML-RPC 7363, ARQ 7323, KISS 7344/7345)
        |-- XML-RPC --> FLMSG  (flmsg --flmsg-dir .../NBEMS-websdr.files/)
        '-- XML-RPC + ARQ --> FLAMP  (flamp --config-dir .../NBEMS-websdr.files/)
```

- **Audio**: FLDIGI is set to PortAudio, with its capture and playback devices set by name
  (index -1, so it looks them up by name rather than by a number that can change).
- **Settings are re-applied, not just checked.** FLDIGI rewrites `fldigi_def.xml` when it
  exits, so the launcher edits it only while FLDIGI is stopped: every start switches off rig
  control, every PTT method, PSKReporter/DX-cluster/eQSL/LoTW, transmit RSID and pre-tone, and
  FLDIGI's own program autostart; sets its own ports; and points *open received message* at a
  wrapper that runs this station's FLMSG. It then re-reads the file and refuses to start unless
  the result is receive-only. Settings missing from the file are added.
- **The launcher starts FLMSG and FLAMP itself** (after FLDIGI's XML-RPC port opens), with this
  station's folder and ports, instead of relying on FLDIGI's autostart.
- **RSID does the mode switching.** Fresh settings start with receive RSID on (still
  listening after each RSID, and switching the modem rather than only notifying), so FLDIGI
  follows a net that changes modes - e.g. Contestia for the net, MFSK-32 for FLMSG/FLAMP
  traffic. Receive RSID only listens; transmit RSID (before and after a transmission) is
  switched off at every start. A copied setup keeps its own receive RSID choice.
- **A copy, never the original**: the first start copies `fldigi.files` and rewrites the copy's
  absolute paths (either slash style) to point at the copy. `fldigi.files` and `NBEMS.files` are
  only ever read.
- **Paths on command lines** are passed with forward slashes and a trailing `/`: a trailing
  backslash before a closing quote would swallow the quote under Windows' argument rules.
- **Stopping**: FLAMP and FLMSG are closed first. FLDIGI is asked to close over XML-RPC
  (`fldigi.terminate`), because being killed makes it exit without saving its settings;
  force is only the fallback.
