# Mouse Trap native/replay tail prefix investigation — 2026-10-13

## Finding

The two F9-tail digit mismatches are the first two outputs of a retained-Z80-register-dependent startup sequence. The evidence localizes the differing value to register B: the native CPU emits `46,47` at port `$EF`, while the state-conditioned T80 replay emits `45,46`. Only D0 is used as the CVSD digit, so these pairs are `0,1` versus `1,0`. The third output byte is `$55` in both runs, and every later bit in the 220,254-event F9 interval matches by ordinal. This identifies where the two bits come from; it does not recover the native register snapshot or prove why the retained B values diverged.

| Native PA release group | Native first writes | Replay first writes | D0 bits (native / replay) |
|---|---|---|---|
| First `EF→F8→FF` | `$08,$09,$2D` | `$00,$01,$2D` | `0,1,1` / `0,1,1` |
| Second `EF→F8→FF` | `$05,$06,$2D` | `$03,$04,$2D` | `1,0,1` / `1,0,1` |
| Third `EF→F9→FF` | `$46,$47,$55` | `$45,$46,$55` | `0,1,1` / `1,0,1` |

Native `bus.csv` records PC `$0016` for each of the first two `$EF` writes in the third group. The staged speech ROM bytes at `$0013–$0016` are `78 D3 EF 04`: `LD A,B`; `OUT (EF),A`; `INC B`. The replay's full I/O addresses are `$45EF` and `$46EF`, with the same data bytes `$45` and `$46`, exposing the value loaded from B. Thus the first OUT uses B, the second uses B+1, and native/replay B values at that point are `$46` and `$45`. The ROM's reset-entry path before that instruction sets C, A, and DE and polls the CVSD clock; it does not change B. This matches the two differing D0 values, followed by convergence at `$55`.

## Why the native state is warmer

The native reference began at machine startup, while the T80 replay starts with the captured post-start command groups and zero-initialized register banks. Native `bus.csv` shows voice-Z80 activity from 11.733 µs, the first `$EF` digit-port write at 50.286 µs, and 592,906 low-A4 writes before the first later PA reset at 38.327199219 s. The Exidy sound-board trace shows an earlier `EF` reset assertion at frame 322 / 5.371760202 s and `FF` release at 5.371779199 s. After that release the voice CPU runs for about 32.955 s before the frame-2299 reset. The first measured replay group does not include this free-running interval.

Pinned MAME `z80_device::device_start` initializes BC to zero; `device_reset` sets PC, WZ, I, R, IFF, and control state but leaves BC unchanged. The Mouse Trap `cvsd_data_w` handler maps PA4 to the voice CPU reset line. Its RC timer independently toggles the MC3417 clock, and the voice-port write handler independently delivers D0 to the decoder. The source does not reset the MC3417 on PA4. The T80 `RegsH/RegsL` arrays likewise have no reset input, while the replay's generated simulation copy initializes them to zero at startup. Both CPUs preserve register-bank contents on later PA4 resets, but the native and replay histories entering the first replayed group differ.

At the first native post-start group, the first byte `$08` versus replay `$00` already shows that a full-byte register comparison cannot be inferred from D0 equality. The two prior groups happen to have matching D0 at their first two writes despite different B values; the third group's one-bit B difference flips both bits. This is consistent with native startup history and omitted free-running voice-CPU time, but the available capture has no direct BC snapshot at the frame-2299 or frame-2371 PA reset. The first F9 OUT lets us infer B=`$46` at that point from the ROM path; it does not expose the full state image or prove the earlier point at which native and replay B diverged.

## Decoder-state boundary

The native MC3417 has been clocked continuously by the MAME RC timer, including while the voice CPU is reset. The replay decoder is cold-reset at replay startup, then retains its state across the simulated PA4 resets. Its 23 logged checkpoints match the pinned MAME bit-event method when given the replay's reconstructed falling-edge stimulus, but there is no native internal-state checkpoint in the capture. Therefore the arithmetic check validates replay decoder state at sampled endpoints; it cannot turn the two native/replay input-bit differences into a native PCM comparison or recover the decoder's pre-F9 filter/history state.

## Evidence limits and next targeted observation

No guessed phrase name or sound effect is attached to either bit pair. A direct follow-up should add native Lua snapshots of the speech CPU's `BC`, `PC`, `AF`, `DE`, `HL`, and alternate register pairs on each accepted sound-board PA callback, plus the first two `$EF` digit writes after each reset release. The pinned MAME state table exposes these named registers. This would preserve the true reset-retained CPU state without a full instruction trace. To test replay sensitivity, a separate simulation-only fixture could seed B from that measured snapshot and run only the ROM's reset-entry prefix; it must not change production cold-start initialization. Native MC3417 parity would require a separate internal-state tap or a reconstructed, edge-accurate complete decoder history and remains outside this CPU-prefix finding.

Evidence comes from `simulation/mousetrap_voice_gameplay_postdelay_busy_tail_3600/bus.csv`, `simulation/mousetrap_native_replay/modelsim-20261013-003910-852/{io.csv,pa.csv}`, the staged `simulation/expansion_adapter/rom-images/mtrap.hex`, and the pinned MAME source snapshot under `simulation/reference_sources/`. All captures and private ROM content remain ignored simulation data.
