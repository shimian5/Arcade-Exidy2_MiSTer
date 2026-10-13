# Mouse Trap native gameplay follow-up — 2026-10-13

## Result

The native MAME run now reaches a verified playable maze and produces post-start sound-board PA callbacks. A 512-frame deliberate VBlank delay explained why earlier input schedules missed the startup path: ROM code at `A1A7` executes `BIT $1F; BPL $A1A7; RTS`; caller `A0C7` sets A=2 and calls `A1AC`, which performs two outer iterations of 256 IRQ-cleared waits. Stack snapshots during the wait show the `A1B9/A1B1/A0C9` return chain and RAM `$1F=08`. Thus the useful input window begins after roughly 8.5 seconds / frame 2010.

A source-backed ordinary coin/start schedule succeeds without CPU/RAM/RIOT pokes: Coin 1 at frame 2100, 1 Player Start at 2160, then movement/action inputs from frame 2220. Screenshots show Hall of Fame at 2040, `CREDITS 01 / PRESS ONE PLAYER START` at 2160, `GET READY PLAYER 1` at 2280, and the playable maze at frame 2400, still active at 2700. The exact input bytes and complete captures are preserved in the private ignored run directory `simulation/mousetrap_voice_gameplay_postdelay_gameplay_wav/`.

## Native sound evidence

The MAME executable is 0.288 (`DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`); staged `mtrap.zip` SHA-256 is `4F87B2C49FCEE00B2A4B7ACD4227EA50229C622F8ADBD4F840B8630EFB55EEE6`. The runner uses `-sound none` to keep host playback muted and optionally `-wavwrite` to capture the emulated output. This produced a 48 kHz mono 16-bit WAV with 2,160,001 frames, peak 15,235, RMS 1,506.578, and SHA-256 `78B3E217CFA17E2841F6017F4A172E8BF7E4A4BA3A1881C71F2CB39BAB5877D7`. The pinned Exidy sound device creates and updates its 6840 stream regardless of host sink selection. The WAV is nonzero and the CPU/RIOT/voice bus record normalized to 3,073,417 identical events between the WAV and no-WAV runs, supporting that audio capture did not perturb the recorded digital execution.

All post-start accepted RIOT PA aliases use `(address & 4) == 0`; DDRA remains `1F`. The following ORA writes resolve directly to full PA output bytes:

| Frame | Time (s) | ORA/callback | Meaning established by source |
|---:|---:|---:|---|
| 2299 | 38.327199219 | `EF` | PA4 low; voice CPU reset asserted |
| 2299 | 38.327331079 | `F8` | PA4 high; voice CPU released |
| 2299 | 38.327914394 | `FF` | subsequent PA output update |
| 2312 | 38.543589910 | `EF` | voice CPU reset asserted |
| 2312 | 38.543757529 | `F8` | voice CPU released |
| 2312 | 38.544340843 | `FF` | subsequent PA output update |
| 2371 | 39.525022182 | `EF` | voice CPU reset asserted |
| 2371 | 39.525189801 | `F9` | voice CPU released; dog input rose at frame 2370 |
| 2371 | 39.525696010 | `FF` | subsequent PA output update |

These groups establish real game-time reset/release callbacks, not bark/meow/chomp identities. The last group follows a Dog-button edge by one frame; the earlier groups occur during Right-held input. No semantic phrase label is assigned without speech/visual correlation.

The Z80 emits 928,480 digit-port writes in the 45-second native run. Captured digit-bit segments bracketed by reset-release writes have lengths 3,341, 15,176, and 7,341. Busy PB0 candidates and every transition, voice clock, and CPU access remain in `bus.csv`; WAV and CSV hashes are also recorded in the run manifest/evidence files. These are native reference data, not values inferred from arbitrary fresh CPU state.

## Reproduction

Run from the repository root:

```powershell
tools/mame/mousetrap_voice_gameplay.ps1 -Run postdelay_gameplay_wav -Frames 2700 -InputProfile postdelay -CaptureWav
```

This path uses ordinary coin/start/action inputs. `IN2` Free Play is a separate optional cabinet configuration and is not needed here; MAME Lua `field.user_value=0` is the DIP-setting API, whereas `field:set_value()` is a digital override.

The MAME source snapshot in `simulation/reference_sources/` backs the input, interrupt, callback, and 6840-stream behavior. The capture outputs are ignored simulation artifacts. No ROM bytes, production RTL, releases, or owner probe files were changed.

## Follow-up replay scope

The native capture is now a valid reference for a state-conditioned T80/speech replay. It does not mean a cold T80 can reproduce the 38-second game history. Any replay should explicitly feed the captured resolved PA groups and elapsed boundaries into the actual T80 plus production speech modules, and report full digit/port equality separately from sampled MC3417 bits and PCM comparisons.
