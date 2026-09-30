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

## If you encounter crash

<img src="img/crash_dialog.png" alt="Crash Dialog" width="1000"/>

If you see the crash dialog, click **Accept**, there will be a log file in the following directory.

Windows: `%USERPROFILE%\Documents\ssb_runner\log`

macOS: `~/Documents/ssb_runner/log`

Linux: `~/Documents/ssb_runner/log`

Please [open an issue](https://github.com/SSBContestRunner/ssb_runner/issues/new) and attach the log file to it.
