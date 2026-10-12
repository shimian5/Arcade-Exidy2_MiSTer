# Mouse Trap actual-firmware decoder join - 2026-10-12

## Bounded acceptance

The private 16 KiB speech image runs on the actual T80 instruction/bus logic through `speechRomBus` and `mousetrapVoiceIo` into the unbound `exidyMc3417`. The nominal CPU enable is 1.7897725 MHz (14.31818 MHz / 8). An ideal fixture oscillator uses the MAME RC half-period of 32.321520 us (15,469.5695 Hz); firmware clock status and decoder input share that clock state. This is a candidate simulation, not production speech support.

The 200 ms command-0x11 run passes with 81,212 ROM read requests, 9,180 IN transactions, 3,093 OUT transactions, 3,093 decoder samples and 3,092 nonzero samples. There are no memory writes. Sampled digits include 1,538 zeros and 1,555 ones. Every decoder sample matches the actual pinned MAME method driven by the **same captured RTL bits**, with exact three-bit history and maximum sample error **0.054932 of a 16-bit PCM step**, below the 0.5-step limit. State values remain within half a normalized 16-bit quantum. This is decoder arithmetic parity, not native MAME CPU/bitstream or audible-phrase parity.

The guarded final run is `simulation/mousetrap_firmware/modelsim-firmware-20261012-113048-513/`. Its manifest records command, ROM payload hash and original/compiled register-source hashes. CSVs, oracle output and comparison JSON remain ignored. The ROM payload hash is `96aabec1a71953afb98f4a28d090c9d2b3564cf7b487cf55604c96aaeba23bf0`, matching the existing increment-07 manifest. No ROM bytes are embedded in committed source.

## Idle-command native prefix

A second 200 ms run uses the native initial callback FF: `simulation/mousetrap_firmware/modelsim-firmware-20261012-113147-636/`. It passes with 80,369 ROM requests, 10,487 INs, 3,094 OUTs and 3,093 samples. Same-bit pinned-method replay passes with maximum sample error **0.006912 PCM LSB**; sampled digits are 1,547 zeros and 1,546 ones.

The **first 3,093 accepted digit writes** match the passive native MAME capture in ordered low-byte port and D0, without dropping a prefix or searching for an offset. This qualifies the initial idle digit sequence only. Timing is different: the first native digit write is 50.286 us, while the fixture's is 88.385 us. Clock first phase, CPU startup/reset and read/bus timing still require reconciliation before PCM or cycle equality. The checker deliberately masks the high I/O address byte because the native map is eight-bit. Idle bits are not evidence of spoken words. The post-boot game inputs in the native capture yielded no later ORA/DDRA speech-command writes.

## Explicit boot assumption and negative control

The original T80 register-bank declarations have no initial values. With those original declarations the firmware's first digit OUT contains an unknown bit, rejected at 88.385051 us by the fixture. The controlled negative run is `simulation/mousetrap_firmware/modelsim-firmware-20261012-113012-540/`; its fatal message is `unknown actual-ROM I/O write from uninitialized CPU register bank`.

The positive fixture generates a simulation-only copy of **T80_Reg.vhd**, adding zero declaration initialization to `RegsH` and `RegsL`. The instruction implementation, register-bank operations and production CPU source are unchanged. Source guards demand exactly one matching declaration per bank. The runner records both SHA-256 hashes. Pinned MAME Z80 `device_start` initializes general and alternate register pairs to zero; `device_reset` does not reset those pairs. T80's AF/SP reset contract also differs from MAME, so this does not establish instruction-cycle equality. Production cold-boot values and warm-reset register retention require explicit validation before binding speech.

Official source: [pinned Z80 implementation](https://raw.githubusercontent.com/mamedev/mame/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/devices/cpu/z80/z80.cpp), locally staged SHA-256 `20101a223b70db55ab61b52924d8b7f23556cad104ee52b4332077a949622cb3`. Decoder method/source pin and prior standalone fit remain documented in [MC3417 qualification](mc3417-decoder-2026-10-11.md).

## Reproduction

From the repository root in PowerShell, with the private staged image already present:

```powershell
./sim/mousetrap_speech/run_mtrap_decoder.ps1
# Intentional failing control: unknown register-bank values must be rejected.
./sim/mousetrap_speech/run_mtrap_decoder.ps1 -RawRegisters
```

The successful runner prints its unique ignored run directory. Prepare an oracle stimulus with `python tools/mousetrap_speech/compare_decoder.py prepare <run-dir>`, run the oracle produced by `tools/mc3417/prepare_reference.py` with `<run-dir>/oracle-stimulus.txt` and `<run-dir>/oracle-reference.txt`, then use `python tools/mousetrap_speech/compare_decoder.py check <run-dir>`. For the FF run, add `--native-capture simulation/mousetrap_voice_capture_20261012/mousetrap_voice_bus.csv` to check the ordered initial digit-write prefix. The existing oracle is a WSL executable; use Linux paths when running it. The oracle extracts the pinned MAME method rather than reimplementing the algorithm in the checker.

The fixture rejects unknown I/O writes and decoder state. It checks meaningful ROM/IN/OUT/sample coverage. The comparison checks oracle row count, stimulus, history, normalized state, decoded output and RC sample interval. All generated files must stay under ignored `simulation/`.

## Remaining gates and next unit

The [passive native MAME capture](mousetrap-voice-reference-2026-10-12.md) is independent reference evidence. No equality claim between its native bitstream and the fixture follows from this arithmetic check. Command 0x11 is an explicit diagnostic callback byte, not a demonstrated game-issued phrase. The fixture does not include the full audio CPU/RIOT/command crossing or expansion bridge; those boundaries have separate synthetic qualification.

Next bounded unit: qualify MAME stream interpolation and stopped-clock silence, then board filter/gain and bounded mono mixing using replayable samples. In parallel preparation, identify a native game-issued speech command and compare its ordered command/clock/digit trace with actual-ROM execution, including boot/reset state. Production command CDC/accepted-write wiring, loader/readiness/reset/pause, real oscillator implementation, full-core Quartus timing and HDMI/Direct Video listening acceptance remain open. No fitted RTL or release file changed in this increment; the latest production build remains `020b2ae`.
