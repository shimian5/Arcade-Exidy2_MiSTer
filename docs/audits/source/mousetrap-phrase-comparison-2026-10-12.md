# Mouse Trap native phrase-stream comparison - 2026-10-12

## Result and scope

The comparator processed the corrected native gameplay capture through frame 3,600 (60 seconds): 928,480 accepted CVSD digit writes. The native summary counted 3,509 audio RIOT bus writes; the filtered trace saved the four relevant PA/DDR setup writes, of which three are PA callbacks. The corrected tap preserves MOS6532 mirrored PA/DDR addresses and excludes timer addresses with A2 set. The native stream has three PA callbacks: `E0`, `EF`, and `FF`; PA4 releases the voice CPU on the final `FF`. There are no later PA callbacks during this capture, so no later game-issued speech command or phrase is evidenced.

The available 200 ms actual-ROM T80 I/O trace (static diagnostic command byte `FF`, simulation-only zeroed T80 register banks) contains 3,093 digit writes. Every production write matches the native capture's ordered prefix by low-byte port and D0; 925,387 native writes remain beyond the production run. Complete stream equality is therefore false and remains unqualified. The comparator reports this unmatched length instead of trimming, offset-searching, or treating the unmatched native tail as tested.

The first digit timestamps are 50.286 us native and 88.385 us in the T80 run. Median inter-digit intervals are 59.784 us native and 59.785 us production; among 3,092 aligned intervals, 240 match exactly, 734 are within 0.1 us, and the largest absolute difference is 12.293 us. Clock phase is distinct from event time: all 3,093 matched writes have the same sampled clock level, even though the first-write times differ by 38.099 us and individual interval deltas reach 12.293 us.

## Command, reset, and replay boundary

The native voice Z80 remains held while PA4 is low and is released at the captured `FF` callback. The T80 run injects one synthetic callback of `FF`; its command byte matches the final native callback but it does not replay the native startup sequence (`E0`, `EF`, `FF`) or its delays. The T80 fixture also simulation-initializes the register banks to mirror MAME construction; this does not certify cold boot or warm-reset behavior in production hardware. A production replay that uses actual RIOT callbacks and reproduces the reset/cadence boundary remains required before claiming that the native startup sequence is integrated end to end.

The comparison is digital bus evidence only. It does not claim identical decoder PCM or WAV output across native and production renderer/filter paths. The bounded corrected capture verifies RIOT mirror handling and current input activity, not that all possible gameplay commands have been exercised. A longer production/boot trace is needed to cover the same native digit window and command/reset cadence. If later gameplay produces ORA/DDRA callbacks, command names must come from that observed PA trace and ROM behavior rather than arbitrary byte values.

## Reproduction

Run the source comparator against a native bus capture and an actual-ROM T80 trace:

```powershell
python sim/mousetrap_phrase_compare/compare_streams.py `
  simulation/mousetrap_voice_gameplay_lateBoot/bus.csv `
  simulation/mousetrap_firmware/modelsim-firmware-20261012-113147-636/io.csv `
  simulation/mousetrap_firmware/modelsim-firmware-20261012-113147-636/run-manifest.json `
  simulation/mousetrap_phrase_compare/native-vs-production-2026-10-12.json

python -m unittest discover -s sim/mousetrap_phrase_compare -v
```

The JSON report and generated traces stay under ignored `simulation/`. `compare_streams.py` streams the large MAME CSV, checks complete available ordered digit sequences and cadence, applies the MOS6532 low-two-bit register decode to PA callback writes, and records the production command assumption. It makes no exact PCM/WAV equality claim.

Parent replay against the final late-input 3,600-frame native capture gives the same 3,093-write prefix match and zero clock-level mismatches, with 925,387 native digits outside the available T80 trace. The [native gameplay audit](mousetrap-native-phrases-2026-10-12.md) documents the Hall of Fame screen and the absence of post-setup PA callbacks; this is not a game-issued phrase replay.
