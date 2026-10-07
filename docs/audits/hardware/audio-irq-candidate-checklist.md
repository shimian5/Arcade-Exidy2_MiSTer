# Audio and interrupt candidate acceptance

This is an owner hardware checklist, not a completed test record. Use the exact RBF identified in the latest [stopping point](../../../STOPPING_POINT.md). Release files remain the comparison baseline. Record settings and failures before changing MRAs, volume or output paths.

## Record the setup

Owner supplied on 2026-10-07: test HDMI and Direct Video through S-Video to a 15 kHz JVC display (owner description: JVC BVM). Exact model, converter/adapter and MiSTer settings still need recording. Teeter Torture must support a spinner plus joystick/D-pad mapping following local Super Off Road or VCO. FAX uses four answer buttons per player in the MRA. These are implementation requirements, not completed hardware tests.

- [ ] RBF path, SHA-256 and matching production commit.
- [ ] MRA name/hash and profile byte; MiSTer main version and relevant INI settings.
- [ ] Audio output connection and whether both channels are monitored.
- [ ] Video display/adapter; for CRT, model, sync type and Direct Video/analog configuration.

## Audio with baseline MRAs

| Game | Required observation | Result / sequence / duration |
| --- | --- | --- |
| Venture | Boot completes; music and effects audible through both channels; effects, firing, room entry and return remain correct | |
| Mouse Trap | Boot/gameplay sound, polling-dependent effects and reset/reload work; voice remains a separate unsupported CVSD path | |
| Pepper II | Music/effects, stage transition and death/restart work | |
| Hard Hat | Music/effects, stage transition and death/restart work | |

- [ ] Check pause/resume during music and an effect, including repeat pause and reset while paused; audio and audio CPU recover together.
- [ ] Reload the same game and switch between an audio-CPU game and Targ/Spectar; check for stale mute, filter state or boot failures.
- [ ] Compare with released RBF at matched volume. Record what improved, regressed or remained wrong; a pitch change alone is not waveform/level acceptance.

## Candidate interrupt MRAs with the same RBF

| Game | Baseline profile | Candidate | Required observation |
| --- | --- | --- | --- |
| Venture revision 5 | `0x10` | `candidates/mra/Venture Revision 5 (int-profile test).mra`, `0x50` | Maze/room entry, firing, object/background collisions, death and room return |
| Pepper II | `0x30` | `candidates/mra/Pepper II (int-profile test).mra`, `0xB0` | Collision/death behavior and complete stage transitions |
| Hard Hat | `0x30` | `candidates/mra/Hard Hat (int-profile test).mra`, `0xB0` | Collision/death behavior and complete stage transitions |

- [ ] Repeat identical inputs with baseline and candidate MRAs; use the same ROM set and settings.
- [ ] Record any lockup, impossible collision, extra interrupt symptom or missing sound, including an exact input sequence and time after boot.
- [ ] Keep Venture arrow I05 open unless the specific inside-room horizontal-shot symptom is reproduced and compared. The fragment replay does not identify the projectile.

Do not mark a game or W15 complete from this checklist alone. Full CPU/frame parity, all supported sets, complete constrained timing, CVSD/missing-game support, CRT transport and remaining audio references have their own gates in [WORKPLAN.md](../../../WORKPLAN.md).
