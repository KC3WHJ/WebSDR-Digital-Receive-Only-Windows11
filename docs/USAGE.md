# Using it

## JS8Call + CommStat: a session, start to finish

1. **Start the station.** Run `websdr-js8-start` in Terminal, or use *Start WebSDR JS8Call +
   CommStat* from the Start Menu or Desktop. It checks the JS8Call profile is receive-only,
   checks the virtual cable is there, starts JS8Call, waits for its API port, then starts
   CommStat.
2. **Play a web SDR.** In your browser, open a WebSDR (e.g. from websdr.org) or a KiwiSDR,
   start its audio, and tune it to a JS8 frequency in **USB** mode.
3. **Route the audio.** The launcher opens *Settings > System > Sound > Volume mixer*.
   Under *Apps*, find your browser (it only appears while it's playing) and set its
   **Output device** to **CABLE Input**. Back in the launcher, press Enter: it checks who is
   playing into the cable and says, for example, *Routed: firefox is playing into 'CABLE
   Input (VB-Audio Virtual Cable)'*. You won't hear the WebSDR now; that's expected.
4. **Watch it decode.** JS8Call shows decoded traffic; CommStat, which connected to JS8Call
   automatically, shows heard stations and any STATREPs on its map and lists.
5. **Stop.** `websdr-js8-stop` (or the *Stop* shortcut) closes both apps. If your browser is
   still set to the cable, it opens the Volume mixer so you can set it back to **Default**.

You can close the launcher's window at any time; JS8Call and CommStat keep running until
you stop them.

### The first time: check JS8Call's audio devices

Open JS8Call's *File > Settings > Audio* once. **Input** should be *CABLE Output* and
**Output** *CABLE Input*. If either shows something else (some Windows audio back ends
shorten device names, so the saved name may not match), pick the cable there and click OK -
JS8Call remembers it.

## Tuning the web SDR

JS8 is a weak-signal mode sent as audio tones, so the SDR must be in **USB** with a passband
wide enough to carry roughly 500-2500 Hz of audio (a normal USB passband is fine). Set the
SDR's dial to the JS8 dial frequency; signals then appear at their audio offsets in JS8Call's
waterfall.

| Band | MHz | | Band | MHz |
|---|---|---|---|---|
| 160 m | 1.842 | | 17 m | 18.104 |
| 80 m | 3.578 | | 15 m | 21.078 |
| 40 m | 7.078 | | 12 m | 24.922 |
| 30 m | 10.130 | | 10 m | 28.078 |
| 20 m | 14.078 | | 6 m | 50.318 |

40 m and 20 m are good places to start. JS8Call has no radio to tune, so the frequency it
displays is only informational: set its band to match what you tuned the SDR to.

**Audio level:** adjust the volume on the WebSDR/KiwiSDR page (or the browser's slider in the
Volume mixer). JS8Call's level meter should sit roughly in the middle - not pinned at the top,
and not near zero. Leave the cable's own level in *Sound settings* at 100%.

## Which browser to route

Windows sends a program's audio to one device - all its tabs together. So while the browser
is routed to the cable, nothing it plays reaches your speakers. The easy fix is to use a
second browser just for the WebSDR (for example Firefox for the WebSDR, Edge for everything
else). Then you never need to switch your normal browser back and forth.

## CommStat

CommStat's connector is created for you (named `WebSDR`, auto-connect on, RF Ack off). The
first time, you may want to use **Manage Groups** to add the groups/nets you follow, and
optionally add a **QRZ** login for callsign look-ups.

CommStat connects to JS8Call **once, at startup**, so JS8Call has to be running first -
`websdr-js8-start` takes care of that order. If you restart JS8Call on its own, open
CommStat's *JS8 Connectors* dialog, select the `WebSDR` row and click **Reconnect**.

## Options

| Command | Effect |
|---|---|
| `websdr-js8-start -NoRoute` | Start the apps but skip the audio-routing step. |
| `websdr-js8-start -NoCommStat` | JS8Call only. |
| `websdr-js8-start` again | Safe at any time: everything already running is reused, and it re-checks the routing. |
| `websdr-audio-check` | Lists audio devices and which programs are playing into each cable. Changes nothing. |

## Changing settings

Settings live in `%APPDATA%\websdr-js8\config` (plain `KEY=VALUE` lines):

| Key | Default | |
|---|---|---|
| `PROFILE` | `WebSDR` | JS8Call profile name (`js8call -r WebSDR`) |
| `TCP_PORT`, `UDP_PORT` | `2443`, `2238` | JS8Call's API ports |
| `JS8_PLAY_DEVICE` | `CABLE Input` | the cable end the browser plays into |
| `JS8_REC_DEVICE` | `CABLE Output` | the cable end JS8Call records from |
| `JS8_TX_DEVICE` | (the cable) | where JS8Call's transmit audio goes |
| `FL_PLAY_DEVICE`, `FL_REC_DEVICE`, `FL_TX_DEVICE` | same cable | the FLDIGI station's devices - set a second cable to run both stations at once |
| `FLDIGI_DIR`, `NBEMS_DIR` | `%USERPROFILE%\fldigi-websdr.files`, `...\NBEMS-websdr.files` | the FLDIGI station's folders |
| `FL_XMLRPC_PORT`, `FL_ARQ_PORT`, `FL_KISS_IO_PORT`, `FL_KISS_OUT_PORT` | `7363`, `7323`, `7344`, `7345` | the FLDIGI station's ports |
| `JS8CALL_EXE`, `FLDIGI_EXE`, `FLMSG_EXE`, `FLAMP_EXE` | (found automatically) | program locations, if they're somewhere unusual |
| `COMMSTAT_SCALE` | (blank = normal) | draw CommStat smaller, e.g. `0.8`, when its window (about 1360x768) doesn't fit your screen - common on laptops at 150% Windows scaling. Restart the station to apply. |

Device names match exactly or by their beginning: `CABLE Input` matches
`CABLE Input (VB-Audio Virtual Cable)`. `websdr-audio-check` shows the exact names. Environment
variables named `WEBSDR_JS8_<KEY>` override the file. Callsign, grid and state are also stored
inside JS8Call's and CommStat's own settings; change them there.

## FLDIGI + FLMSG + FLAMP: a session, start to finish

1. **Start the station.** Run `websdr-fldigi-start`, or use *Start WebSDR FLDIGI + FLMSG-FLAMP*.
   The first time, it creates the station's own settings: a copy of `%USERPROFILE%\fldigi.files`
   (so your macros, frequency list and modem settings carry over) in `fldigi-websdr.files`, and
   FLMSG/FLAMP settings in `NBEMS-websdr.files`. If you've never run FLDIGI, it starts from fresh
   settings with the callsign and grid you gave the installer.
2. Every start then switches off rig control, PTT and spotting, points FLDIGI at the cable, and
   starts FLDIGI, then FLMSG and FLAMP.
3. **Play and tune a web SDR** in **USB** mode, to the dial frequency you'd use on a radio.
   Signals appear at their audio offsets in FLDIGI's waterfall (for example an AmRRON net on
   7.110 MHz dial with Contestia at 900 Hz).
4. **Route the audio** the same way as for JS8Call, and press Enter.
5. **Watch it decode.** Click a signal in the waterfall, or let RSID switch the mode for you.
   Received FLMSG forms open in FLMSG; FLAMP collects received files in
   `NBEMS-websdr.files\FLAMP\rx`.
6. **Stop.** `websdr-fldigi-stop` closes FLAMP, FLMSG and FLDIGI (asking FLDIGI to close
   itself, so it saves its settings).

The first time, check *Configure > Sound Card > Audio devices* shows **PortAudio** with
*CABLE Output* as Capture. If not, pick it there; the launcher sets the device name at every
start, so if a shortened name is what FLDIGI shows, put that name in `FL_REC_DEVICE`.

**Both stations at once** needs two cables (one per station), because both would otherwise hear
the same audio. Install a second cable (VB-Audio *Hi-Fi Cable*, or *CABLE A+B*), set
`FL_PLAY_DEVICE` / `FL_REC_DEVICE` to it, and route a second browser to it. The launchers warn
if you start both on one cable.
