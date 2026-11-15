# SSB Runner

![logo](img/logo_128.png)

SSB Contest Listening and Training Software

inspired by [MorseRunner](https://github.com/w7sst/MorseRunner)

## Training capabilities

- Rule registry with CQ WPX SSB, CQ WW SSB, ARRL DX SSB, IARU HF SSB, and
  JIDX SSB practice templates.
- Run, Search & Pounce, and overlapping-caller Pile-up exercises.
- Beginner, Standard, and Advanced audio profiles: playback speed, a constant
  receiver noise bed, in-signal noise, and QSB fading.
- Deterministic practice seeds. A session records a `questionSeed` (callsigns,
  exchanges, pile-up candidates, phonic choices) and an `audioSeed` (noise bed,
  in-signal noise, QSB phase) so a session can be reproduced or fully replayed
  from its recorded answer log.
- Post-session review with QSO count, accuracy, rate, score, error categories,
  and a one-click replay of the same practice seed.
- Configurable F1–F8 commands and incoming-station audio volume.

The additional templates are explicitly **single-band training profiles**.
They are not Cabrillo-log certification: official multi-band scoring also needs
the event's category, band, date, and current rule revision.

## Downloads

Please visit our [website](https://ssbrunner.com/) 

or download release from [Releases Page](https://github.com/SSBContestRunner/ssb_runner/releases) in GitHub

### Supported platforms

Only the desktop platforms below are packaged and released; the Android, iOS,
and Web scaffolds are not release targets.

| Platform | Architecture | Minimum version |
| --- | --- | --- |
| Windows | x64 | Windows 10 version 1607 (build 14393) or later, or Windows 11 |
| macOS | Universal — Apple Silicon, Intel (best-effort) | macOS 13 Ventura or later |
| Linux | x86_64 | glibc 2.35+ — Ubuntu 22.04 / Debian 12 or newer |

Windows 10 1507/1511 (build 10240/10586) is not supported: the window-manager
plugin imports an API that only exists from build 14393. The installer refuses
those versions, and the portable zip shows a message and exits before the app
starts. On 1607 the process is DPI-unaware, so at 125%/150% the UI is
bitmap-stretched; per-monitor scaling starts with 1703.

macOS 12 is not supported even though Flutter itself allows it: Flutter 3.47
builds native assets (sqlite3, cnativeapi, flutter_soloud, objective_c) with a
fixed macOS 13 deployment target, and dyld refuses to load those binaries on an
older system. The bundle therefore declares — and must keep — 13.0.

#### Artifacts

- **Windows** (x64)
  - `.exe` — single-file installer; installs per-user without an admin prompt to
    `%LOCALAPPDATA%\Programs\SSB Runner`, with Start menu and uninstall entries.
    The MSVC runtime DLLs are bundled.
  - `.zip` — portable; unzip and run `ssb_runner.exe`. The MSVC runtime DLLs are
    bundled, so no separate VC++ Redistributable is needed.
- **macOS** (universal; runs natively on both Apple Silicon and Intel Macs)
  - `.dmg` — drag **SSB Runner.app** into *Applications*.
  - Intel support is best-effort: the bundle is checked to contain an x86_64 slice, but
    releases are not launched on Intel hardware. Apple ends Intel Mac support with macOS 26.
- **Linux** (x86_64) — all three artifacts require glibc 2.35+.
  - `.deb` — install with `apt`, which also pulls in the EGL/GLES runtime the
    Flutter engine loads.
  - `.AppImage` — mark it executable and run it. It bundles libstdc++ and
    libgcc, but not glibc, so the 2.35 floor still applies. Mounting it needs
    FUSE 2 (`libfuse2` / `fusermount`), which recent distributions no longer
    install by default; without it, run the file with
    `--appimage-extract-and-run`. GTK 3, GL/EGL and ALSA/PulseAudio always come
    from the system.
  - `.zip` — portable; unzip and run.

#### Verifying downloads

Every release publishes a `SHA256SUMS.txt` asset and lists the same SHA-256
fingerprints at the top of the release notes. Check them after downloading:

- **Linux** — run `sha256sum -c SHA256SUMS.txt` in the download directory.
- **macOS** — run `shasum -a 256 -c SHA256SUMS.txt` in the download directory.
- **Windows** — run `Get-FileHash -Algorithm SHA256 <file>` (or
  `certutil -hashfile <file> SHA256`) and compare the value with the release notes.

A matching fingerprint means the file arrived intact. It is not a code
signature, so it does not prove who built the package.

Releases are currently **unsigned**. On first launch:

- **Windows** — SmartScreen may warn about an unknown publisher; choose
  *More info → Run anyway*.
- **macOS** — right-click the app and choose *Open*, or allow it under
  *System Settings → Privacy & Security*.

## If you encounter crash

<img src="img/crash_dialog.png" alt="Crash Dialog" width="1000"/>

If you see the crash dialog, click **Accept**. Log files are written to the
application data directory, under `log/`:

- Windows: `%APPDATA%\com.ssbrunner\ssb_runner\log`
- macOS (release builds run sandboxed):
  `~/Library/Containers/com.ssbrunner.app/Data/Library/Application Support/com.ssbrunner.app/log`
  (non-sandboxed debug builds use
  `~/Library/Application Support/com.ssbrunner.app/log`)
- Linux: `~/.local/share/com.ssbrunner.app/log`

You can also open **Diagnostics → Export logs** in the settings panel, which
saves a zip of the logs into your Documents folder and copies its path to the
clipboard; **Copy diagnostics** puts the summary straight on the clipboard.

Please [open an issue](https://github.com/SSBContestRunner/ssb_runner/issues/new) and attach the log file (or the exported zip) to it.
