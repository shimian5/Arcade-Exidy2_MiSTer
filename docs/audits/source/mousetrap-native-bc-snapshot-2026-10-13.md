# Mouse Trap native speech CPU BC snapshots

## Result

The ordinary MAME gameplay run exposes the warm speech CPU's actual BC register at both the reset-release PA writes and the first two speech-port outputs. For the native third command group, MAME reports BC=`$46BF` at resolved PA=`$F9`, then the two first output writes carry `$46` and `$47` while BC reports `$46BF` and `$47BF`. This directly confirms that the first output uses the live B value and that the following output uses the incremented B value. The paired T80 replay starts this interval one lower (`$45`, `$46`); the native state observations therefore explain the two tail-byte differences without assigning any speech meaning to those bytes.

## Capture method and provenance

Run `simulation/mousetrap_voice_gameplay_bc_snapshot_native_postdelay_final/` used MAME 0.288 with the staged `mtrap.zip`, the `postdelay` profile, and 2,400 frames. It used ordinary Coin 1 at frame 2100, Start at 2160, and game controls. The trace captures only RIOT ORA/DDRA writes used to resolve PA and the first two low-A4 voice I/O writes at boot and after each PA4 reset release. It installs no full bus taps; `bus.csv` contains only its header. The state-only branch also skips screen snapshots and CPU program-space inspection.

The Lua reads debugger register objects through `.value`, protected by `pcall`, for PC/AF/BC/DE/HL/SP and alternate/index/status registers. It makes no CPU address-space reads and does not force register values or speech commands. The live BC probe succeeded (`0000` at initial boot); all 22 recorded rows contain numeric state values. The capture completed at frame 2400 with no Lua error. The run manifest records MAME executable SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`, staged ROM archive SHA-256 `4F87B2C49FCEE00B2A4B7ACD4227EA50229C622F8ADBD4F840B8630EFB55EEE6`, trace SHA-256 `DA667633B5A2348DD786C760775F9D753ACEE96C481693D59B922539DD74E264`, Lua SHA-256 `90B8B3FDE6186B1C5783676F8503BFAC18D4E4E145DA5A76E6BAC1FFA6CC43E1`, and runner SHA-256 `1F19CC08FF6F16DB25EDE6DBB8FDECA3D0DEA966F489638FE7024B8E436EC16E`.

## Observed rows

The reset is represented by PA=`$EF` (speech reset asserted) followed by the release write. Callback rows include the DDRA value and the resolved pin level computed as `(ORA & DDRA) | (DDRA ^ $FF)`.

| Frame / time | Event | Resolved PA or output data | Voice CPU PC / BC |
| --- | --- | --- | --- |
| 322 / 5.371760202 s | Initial PA reset | `$EF` | `$000F / $9ABF` |
| 322 / 5.371779199 s | Initial PA release | `$FF` | `$000F / $9ABF` |
| 322 / 5.371830602 s | First low-A4 output after release | `$9A` | `$0016 / $9ABF` |
| 2299 / 38.327331079 s | Group 1 release | `$F8` | `$0010 / $08BF` |
| 2299 / 38.327431650 s | First output | `$08` | `$0016 / $08BF` |
| 2299 / 38.327498139 s | Second output | `$09` | `$0016 / $09BF` |
| 2312 / 38.543757529 s | Group 2 release | `$F8` | `$006B / $05BF` |
| 2312 / 38.543858100 s | First output | `$05` | `$0016 / $05BF` |
| 2312 / 38.543912297 s | Second output | `$06` | `$0016 / $06BF` |
| 2371 / 39.525189801 s | Group 3 release | `$F9` | `$001A / $46BF` |
| 2371 / 39.525265788 s | First output | `$46` | `$0016 / $46BF` |
| 2371 / 39.525332277 s | Second output | `$47` | `$0016 / $47BF` |

The voice ROM disassembly identifies the output sequence at `$0013–$0016` as `LD A,B`, `OUT (EF),A`, `INC B`. MAME reports PC `$0016` at the I/O callback. At each callback, B matches the output byte; at the second callback, B has advanced by one. The native third-group B seed is `$46`, while the paired replay's corresponding seed is `$45`. This establishes the immediate register/data relationship; it does not reconstruct the native CPU's full warm history or establish phrase completion.

## Scope limits

These rows are native MAME observations for the staged ROM and this exact ordinary-input scenario. The PA4-low endpoint after the final voice group remains a command-interrupted reset transition from the earlier capture, not evidence of natural voice completion. No claim is made that all speech groups completed, that sampled MC/PCM matches native audio, or that a cold T80 initialization models the native warm CPU state.
