# WebSDR-Digital-Receive-Only for Windows

**Receive-only digital-mode stations on Windows 11, fed by any web SDR or KiwiSDR.**
No radio, no antenna, no transmitting: play a WebSDR in your browser, and this sets up
the decoders to listen to it:

- **JS8Call + CommStat** - [JS8Call](http://js8call.com/) decodes JS8 traffic and
  [CommStat](https://github.com/mgochoa57/CommStat) shows what it hears (map, STATREPs).
- **FLDIGI + FLMSG + FLAMP** - [FLDIGI](http://www.w1hkj.com/) decodes PSK, MFSK,
  Contestia, Olivia, RTTY and more; FLMSG opens received forms and FLAMP reassembles
  received files (NBEMS traffic, e.g. AmRRON nets).

This is the Windows port of
[WebSDR-Digital-Receive-Only](https://github.com/KC3WHJ/WebSDR-Digital-Receive-Only)
(Linux). It is a small installer and a set of PowerShell launchers - not a copy of any of
these programs. It installs them with **winget** (keeping any you already have), downloads
CommStat from its own GitHub repository, and configures everything for listening only.

```
 web SDR / KiwiSDR  ->  browser  ->  virtual audio cable  ->  JS8Call  ->  CommStat
                                      (VB-CABLE)              (no rig)     (map, STATREPs)

 web SDR / KiwiSDR  ->  browser  ->  virtual audio cable  ->  FLDIGI  ->  FLMSG / FLAMP
                                                              (no rig)    (forms, files)
```

## What's different on Windows

| Linux version | Windows version |
|---|---|
| PulseAudio/PipeWire "null sinks", created and removed on each start/stop | A **virtual audio cable driver** you install once ([VB-CABLE](https://vb-audio.com/Cable/), free). Windows has no built-in equivalent. |
| The launcher moves one browser *tab* into the decoder (`pactl move-sink-input`) | Windows routes audio **per program**, and has no supported way for a script to change it. The launcher opens *Settings > Sound > Volume mixer*, tells you to set your browser's output to the cable, then **checks that it worked** by listing who is playing into the cable. Use a second browser just for the WebSDR if you want sound from your normal one. |
| Transmit audio goes to a second, discarded null sink | Transmit audio goes into the same cable (configurable). It never leaves the PC; there is no radio to key. |
| `apt` packages | `winget` packages: `JS8Call-improved.JS8Call-improved` (JS8Call 3), `w1hkj.fldigi`, `w1hkj.flmsg`, `w1hkj.flamp`, `Python.Python.3.12` |
| CommStat uses the system Python | CommStat gets its own Python environment (a venv), so its PyQt5 / Qt WebEngine packages can't clash with anything else |
| Clock check via `timedatectl` | Clock check measures the PC's offset from `time.windows.com` directly |

Everything else is the same design: separate settings for every program, receive-only
settings re-checked at every start, and a read-only prerequisite check that refuses to
touch your system if a hard requirement isn't met.

## Receive-only, by design

| Safeguard | What it does |
|---|---|
| No rig control | The JS8Call profile has `Rig=None`, no CAT (serial, network or USB) or PTT port, and no PTT command (JS8Call 3 can run a program on every transmit). FLDIGI's settings have Hamlib, RigCAT and flrig control and **every PTT method** switched off. |
| Start-up guard | `websdr-js8-start` re-checks the JS8Call profile every time and **refuses to start** if rig control, a CAT port, a PTT port or command, or PSKReporter/APRS spotting or APRS-IS relaying has since been configured (or if a spotting setting is missing - JS8Call turns spotting *on* when it is). `websdr-fldigi-start` re-applies FLDIGI's receive-only settings on every start, then checks the result and refuses to start if it isn't receive-only. |
| No automatic transmissions | CommStat's connector is created with **RF Ack off**. FLDIGI's transmit RSID and pre-tone are off, FLAMP's automatic and timed repeats are off, and FLDIGI's own program autostart is off (so a copied setup can't start flrig). |
| No false spotting | JS8Call's **PSKReporter and APRS spotting**, and FLDIGI's **PSKReporter, DX-cluster, eQSL and LoTW** uploads, are all off. Stations heard through a remote receiver must never be reported as if heard at *your* location. |

The programs still show their normal transmit buttons; with no radio behind them they do
nothing on the air.

## Requirements

- **Windows 11** (Windows 10 1809+ should work, untested), 64-bit.
- **winget** (built into Windows 11 as "App Installer").
- A **virtual audio cable**: [VB-CABLE](https://vb-audio.com/Cable/) is free. Run its
  setup as administrator, then restart Windows. (Any other cable works - set its device
  names in the config file.) To run **both stations at the same time**, you need a second
  cable (e.g. VB-Audio *Hi-Fi Cable* or *CABLE A+B*).
- A web browser and an internet connection. About 1.5 GiB of free disk space.
- An accurate clock - JS8 decodes on tight time slots.

## Quick start

1. Install [VB-CABLE](https://vb-audio.com/Cable/) and restart Windows.
2. Get this project - with Git:

```bash
git clone https://github.com/KC3WHJ/WebSDR-Digital-Receive-Only-Windows11.git
```

   or download it from GitHub (*Code > Download ZIP*) and extract it. Then open its folder
   in Terminal / PowerShell (**not** as administrator) and run:

```bash
.\install.cmd -Check
```

```bash
.\install.cmd
```

3. Open a **new** Terminal window (so the PATH change applies), then:

```bash
websdr-js8-start
```

Or use **Start WebSDR JS8Call + CommStat** in the Start Menu / on the Desktop. For the
FLDIGI station: `websdr-fldigi-start`. Don't want it? `.\install.cmd -NoFldigi`.

The `.cmd` files run the PowerShell scripts without changing your execution policy.

You'll be asked for a callsign (or any short ID if you're only listening, such as
`N0CALL`), your grid square, and optionally your US state. Then, for either station:

1. Open a web SDR or KiwiSDR in your browser and start its audio.
2. Tune it in **USB** mode - to a JS8 frequency for JS8Call (for example 7.078 MHz), or to
   the dial frequency you'd use on a radio for FLDIGI.
3. In the **Volume mixer** page the launcher opens, set your browser's *Output device* to
   **CABLE Input**. Press Enter in the launcher; it confirms the audio is arriving.
4. The decoder starts working; CommStat connects to JS8Call automatically, and the FLDIGI
   launcher opens FLMSG and FLAMP for you.
5. When you're done: `websdr-js8-stop` / `websdr-fldigi-stop`, and set the browser's output
   back to **Default** (the stop command reminds you, and opens the page).

Details and tuning tips: [docs/USAGE.md](docs/USAGE.md).

## The prerequisite check

`install.cmd` runs `preflight.ps1` first. It is **read-only** (no changes, no administrator
rights) and marks each item OK, WARN or FAIL. Any FAIL stops the installer before it has
changed anything. It checks:

Windows version and CPU architecture - that it isn't an Administrator window - winget -
free disk space and memory - Python 3.8+ - internet access to GitHub, PyPI and the program
download sites - which programs are already installed - the Windows Audio service - that
your **virtual audio cable** exists (and that it isn't Windows' default output, which would
send every sound into the decoder) - installed browsers - the **clock's offset** from
`time.windows.com` - that your settings and ports are valid and free - and any existing
install (which is kept, never overwritten).

## What gets installed, and where

| Item | Location |
|---|---|
| Programs (winget) | JS8Call 3 ([JS8Call-improved](https://github.com/JS8Call-improved/JS8Call-improved); an existing JS8Call 2.2 is kept and works too), FLDIGI, FLMSG, FLAMP, Python 3.12 - each only if you don't already have it |
| CommStat | `%LOCALAPPDATA%\websdr-js8\CommStat` (downloaded from GitHub) |
| CommStat's Python environment | `%LOCALAPPDATA%\websdr-js8\venv` |
| JS8Call profile | `%LOCALAPPDATA%\JS8Call - WebSDR\JS8Call - WebSDR.ini` |
| FLDIGI settings | `%USERPROFILE%\fldigi-websdr.files` (created at first start - a copy of `fldigi.files` if you have one) |
| FLMSG / FLAMP settings and received messages | `%USERPROFILE%\NBEMS-websdr.files` (FLAMP in its `FLAMP\` subfolder) |
| Settings | `%APPDATA%\websdr-js8\config` |
| Launchers | `%LOCALAPPDATA%\websdr-js8\bin` (on your PATH), Start Menu folder *WebSDR Digital Receive-Only*, Desktop shortcuts |
| Logs | `%LOCALAPPDATA%\websdr-js8\commstat.log` |

Re-running the installer is safe: it keeps an existing JS8Call profile, CommStat database,
connector, and FLDIGI settings.

## Commands

| Command | |
|---|---|
| `websdr-js8-start [-NoRoute] [-NoCommStat]` | Start JS8Call + CommStat |
| `websdr-js8-stop` | Stop them |
| `websdr-fldigi-start [-NoRoute]` | Start FLDIGI + FLMSG + FLAMP |
| `websdr-fldigi-stop` | Stop them (FLDIGI is asked to close itself, so it saves its settings) |
| `websdr-audio-check` | Read-only: lists audio devices and who is playing into each cable |

## Uninstall

```bash
.\uninstall.cmd
```

`-Purge` also removes the JS8Call profile, CommStat folder and FLDIGI/FLMSG/FLAMP folders
without asking; `-KeepData` never removes them. Installed programs are left alone; remove
them from *Settings > Apps*. Your normal `fldigi.files` and `NBEMS.files` are never touched.

## Things worth knowing

- **CommStat talks to its own server.** It sends a periodic heartbeat with your callsign and
  grid, receives the nationwide STATREP feed, and downloads map tiles - so it needs internet.
  What it shows from the radio side is what the WebSDR heard, not your local RF environment.
- **CommStat updates itself** in place from its server.
- **Someone else's receiver has its own rules.** Public KiwiSDRs often limit session length
  and users; follow the operator's terms.
- **Windows routes a whole program, not a tab.** Every tab of the browser you route plays
  into the decoder. Use a browser you don't need for anything else while listening.
- **The FLDIGI station uses its own ports** (XML-RPC 7363, ARQ 7323, KISS 7344/7345) so it
  can run beside a normal FLDIGI (7362/7322).
- **JS8Call's title bar always says "de KN4CRD".** That is the JS8Call author's callsign,
  built into every JS8Call window title. It is not your callsign.

## Testing

`tests\run-tests.ps1` runs 114 checks with no administrator rights, GUI or internet:
validation, settings, command-line quoting, the JS8Call receive-only guard (every way a
profile can stop being receive-only), JS8Call start/stop with a stand-in program (including
leaving another profile's JS8Call alone), FLDIGI's settings copy (rig control, PTT and
spotting off; paths re-pointed; the normal folders untouched; fresh setup when there are
none; the guard catching later changes), audio session detection, the prerequisite check's
failures, and uninstall.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

**Not yet tested on Windows:** the winget installs and CommStat's installer on a clean PC,
and the real JS8Call/FLDIGI/FLMSG/FLAMP binaries with VB-CABLE. The JS8Call 3 settings
names, profile location, `-r` option and name-based audio-device lookup were checked against
its v3.0.3 source code. Check the first time that JS8Call (*File > Settings > Audio*) and
FLDIGI (*Configure > Sound Card*) show the cable as their input: a device name that doesn't
match makes them fall back to your default microphone. If you try it, please report what
you find.

## Credits and licenses

This project only installs and configures other people's software; it does not include or
redistribute it.

- **WebSDR-Digital-Receive-Only** (the Linux original, whose design this follows) - KC3WHJ, MIT.
- **JS8Call** - Jordan Sherer (KN4CRD) and contributors, and the JS8Call-improved developers (JS8Call 3), GPL-3.0.
- **CommStat** - Manuel Ochoa (N0DDK), GPL-3.0, <https://github.com/mgochoa57/CommStat>.
- **FLDIGI, FLMSG, FLAMP** - Dave Freese (W1HKJ), Robert Stiles (KK5VD) and contributors, GPL-3.0.
- **VB-CABLE** - VB-Audio Software (donationware; installed by you, not by this project).

The scripts in this repository are released under the MIT License (see `LICENSE`).
`share/seed_commstat.py` is unchanged from the Linux version.
