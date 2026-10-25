# Troubleshooting

Run `.\preflight.cmd` any time for a read-only health check, and `websdr-audio-check` to see
the audio devices and who is playing into each cable. CommStat's log:
`%LOCALAPPDATA%\websdr-js8\commstat.log`.

## The installer stops with FAIL items

Each FAIL line ends with a hint. Common ones:

| FAIL | Meaning / fix |
|---|---|
| Running as ... (Administrator window) | Open a normal Terminal / PowerShell, not "Run as administrator". winget asks for approval itself where a program needs it. |
| winget not found | Install or update *App Installer* from the Microsoft Store. |
| Cable (JS8Call) not found | Install [VB-CABLE](https://vb-audio.com/Cable/) (run its setup as administrator) and **restart Windows**. Using another cable? Set `JS8_PLAY_DEVICE` / `JS8_REC_DEVICE` in `%APPDATA%\websdr-js8\config` - `websdr-audio-check` lists the exact names. |
| Audio service | Start the *Windows Audio* service (services.msc), or restart Windows. |
| TCP port in use | Something else listens on JS8Call's API port. Set another `TCP_PORT` in the config file. |
| Host: ... cannot reach | Check your connection, proxy or firewall. |

Nothing is installed or changed when a FAIL stops the installer.

## "running scripts is disabled on this system"

Use the `.cmd` files (`install.cmd`, the commands on your PATH, the Start Menu shortcuts): they
run the scripts with `-ExecutionPolicy Bypass` for that one run, without changing your policy.
If your organisation enforces a policy through Group Policy, that can't be bypassed; ask your
administrator.

## Default speakers warning: "every program's sound would go into the decoder"

Some cable installers make the cable Windows' **default** output. Then all sound - not just
the WebSDR - goes into the decoder and you hear nothing. In *Settings > System > Sound*, choose
your real speakers or headphones under *Output*.

## The launcher says "Nothing is playing into CABLE Input yet"

- Is the WebSDR page actually **playing**? Many sites need a click on a play / "start audio"
  button first. A browser only appears in the Volume mixer while it's playing.
- In the Volume mixer, under *Apps*, is the browser's *Output device* set to **CABLE Input**?
  (Not the *Input device*.)
- Some browsers keep a separate audio process; if the choice doesn't stick, close and reopen
  the browser after setting it, then press Enter in the launcher again.

## JS8Call shows nothing / a flat waterfall

- Check the routing (above), and that the SDR is in **USB** on the JS8 dial frequency.
- JS8Call's *File > Settings > Audio > Input* must be *CABLE Output*. If the saved name didn't
  match (some Windows audio back ends shorten names), JS8Call falls back to your default
  microphone. Pick the cable there; JS8Call remembers it.
- Check the clock: `.\preflight.cmd` measures its offset. More than about a second and JS8
  decodes fail. *Settings > Time & language > Date & time > Sync now*; Windows only syncs
  occasionally, so a tool such as Meinberg NTP keeps it accurate.

## I can't hear my browser after I finish

Its output is still set to the cable. `websdr-js8-stop` / `websdr-fldigi-stop` tell you and
open the Volume mixer: set the browser's *Output device* back to **Default**. (The Volume
mixer's *Reset* button resets every app at once.)

## CommStat can't connect / its connector says Disabled

CommStat connects to JS8Call once at startup and disables the connector after repeated
failures. Make sure JS8Call is running, then in CommStat open **JS8 Connectors**, select
`WebSDR` and click **Reconnect**. `websdr-js8-start` always starts JS8Call first. If JS8Call's
API port doesn't open, check *File > Settings > Reporting*: the TCP Server API must stay enabled.

## CommStat doesn't start

Look in `%LOCALAPPDATA%\websdr-js8\commstat.log` and `commstat.log.err`. A missing Python
module means its environment is incomplete: run `.\install.cmd` again (without
`-SkipCommStatDeps`). The map needs internet access for its tiles.

## CommStat's window is too big for the screen

CommStat's window is about 1360x768, which doesn't fit a small laptop screen at 125-150%
Windows scaling. Add `COMMSTAT_SCALE=0.8` (or `0.7`) to `%APPDATA%\websdr-js8\config`, then
`websdr-js8-stop` and `websdr-js8-start`. Only CommStat is drawn smaller.

## "receive-only guard: ..." and it won't start

The JS8Call profile no longer looks receive-only (rig control, a CAT port or a PTT port is set,
or spotting is on - possibly changed from inside JS8Call). The message says which. Fix it in
`%LOCALAPPDATA%\JS8Call - WebSDR\JS8Call - WebSDR.ini`, or delete that file and run
`.\install.cmd` again for a fresh profile.

## FLDIGI shows nothing / a flat waterfall

- Same first checks as for JS8Call: is the WebSDR playing, is the browser routed, is the SDR
  in USB?
- *Configure > Sound Card > Audio devices* should show **PortAudio** with *CABLE Output* as
  Capture. The launcher sets this at every start by name; if FLDIGI lists the cable under a
  shortened name, put exactly that name in `FL_REC_DEVICE` (and the output's in `FL_TX_DEVICE`).
- Running both stations on one cable? Each needs its own cable to hear different frequencies.

## FLMSG or FLAMP doesn't open, or can't reach FLDIGI

The launcher starts them after FLDIGI's XML-RPC port (7363) opens. If FLDIGI was slow to start,
run `websdr-fldigi-start` again - it starts whatever isn't running. A FLMSG or FLAMP you open
some other way connects to a normal FLDIGI (7362) instead.

## FLDIGI's settings changes don't stick

Rig control, PTT, spotting, ports, audio and autostart settings are re-applied at every start,
by design. Other changes (modem settings, colors, macros) are kept, provided FLDIGI is closed
with `websdr-fldigi-stop` or its own File > Exit.

## Updating

- **CommStat** updates itself when its server pushes an update.
- **JS8Call, FLDIGI, FLMSG, FLAMP**: `winget upgrade` (or their own installers).
- **This project:** replace this folder with the new version, then run `.\install.cmd` again (it
  keeps your existing configuration).
