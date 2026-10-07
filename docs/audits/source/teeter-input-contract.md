# Teeter Torture input callback contract

This audit resolves the apparent `0x44` versus bits 4/0 discrepancy in MAME’s Teeter input handler. It also records a local MAME 0.288 capture of scripted DIAL targets and reads of the actual `$5101` input address. It does not change Exidy2 RTL, define a Teeter MRA, or validate gameplay/control feel.

## Result

MAME’s `PORT_CUSTOM_MEMBER` callback return is right-aligned and shifted into the port field mask. The Teeter callback returns an event flag in bit 4 and direction in bit 0 (`0x11` when moving toward a larger dial count; `0x10` when moving toward a smaller count). The `IN0` custom field mask is `0x44`, whose least-significant set bit is bit 2. MAME 0.288’s `dynamic_field::read` shifts the callback return left by that amount and masks it: `(newval << 2) & 0x44`. Thus the actual `$5101` event is bit 6, and direction is bit 2. There is no driver bit-placement mismatch. The callback’s right-aligned byte before MAME places it is `0x11` for a positive count step and `0x10` for a negative count step.

Observed bytes from the MAME capture match this. `IN0` idle baseline was `0xBB`; positive-step reads were `0xFF` (`0xBB | 0x44`); negative-step reads were `0xFB` (`0xBB | 0x40`). The preserved non-dial bits stay at their baseline values in these samples.

The handler consumes exactly one position count on each `IN0` port read while the dial differs from `m_last_dial`. Arithmetic is unsigned 8-bit wrap: `((dial - m_last_dial) & 0xff) < 0x80` advances/increments and sets direction bit 0; otherwise it decrements and clears direction. For example, target `0x00` from saved `0xff` has modulo delta `0x01`, so the first read returns `0x11` and wraps the saved count to `0x00`. Target `0x7f` from `0x00` has delta `0x7f`, so it increments; target `0x80` from `0x00` has delta `0x80`, so it decrements to `0xff`; target `0xff` from `0x00` has delta `0xff` (equivalent to -1), so it decrements to `0xff`. Deltas 127 and 128 show the threshold boundary. Each subsequent read moves one more count toward the target; the event remains asserted until the saved count catches up, then both event bits clear. The actual run exercised positive and negative output bits, while the wrap and half-turn rules are directly visible in the pinned handler arithmetic.

## Evidence and reproduction

- MAME executable: `C:\MiSTerDev\mame\mame.exe`, version `0.288 (mame0288)`, SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`.
- ROM archive staged only under ignored `simulation/teeter-contract/roms/teetert.zip`, 24,439 bytes, SHA-256 `770B05AD8BD7C31A1FB0A5DA700CC6DCDA9EB26D815E0AD16A063EA37F66F61B` (same hash as the read-only NAS source ZIP). No ROM content is committed.
- Official pinned [MAME 0.288 `ioport.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/emu/ioport.cpp): `compute_shift` at lines 85–98 and `dynamic_field::read` at lines 3257–3283 (callback return shifted by the number of trailing zero bits in its mask).
- Official pinned [MAME 0.288 `exidy.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/mame/exidy/exidy.cpp): `teetert_input_r` at lines 405–421, `$5101` mapped to `IN0` at lines 463–475, and Teeter `IN0` mask `0x44` plus reversed 8-bit dial at lines 856–885.
- Reproducible Lua harness: [`tools/reference_cases/teeter_input_capture.lua`](../../../tools/reference_cases/teeter_input_capture.lua). It sets dial targets `0x01`, `0x80`, `0x00`, `0x7f`, `0xff`, samples the `IN0` port once per even frame, and taps actual main-CPU reads at `$5101`. In the local 100-frame run, 50 scripted `IN0` samples were `0xBB` 29 times, `0xFF` 11 times, and `0xFB` 10 times; the `$5101` CPU read tap recorded `0xBB` 34 times, `0xFF` 8 times, and `0xFB` 8 times in its per-even-frame last-read sample. The sample counts include ordinary emulated polling and are not a controlled benchmark of rate or latency.

From the repository root, reproduce after staging the same ROM ZIP in the ignored path:

```powershell
New-Item -ItemType File -Force simulation/teeter-contract/run/readbacks.csv | Out-Null
$env:AUD_OUT = (Resolve-Path simulation/teeter-contract/run/readbacks.csv).Path
& 'C:\MiSTerDev\mame\mame.exe' teetert `
  -rompath simulation/teeter-contract/roms `
  -cfg_directory simulation/teeter-contract/run/cfg `
  -nvram_directory simulation/teeter-contract/run/nvram `
  -input_directory simulation/teeter-contract/run/input `
  -autoboot_script tools/reference_cases/teeter_input_capture.lua `
  -noreadconfig -video none -sound none -nothrottle -skip_gameinfo -seconds_to_run 20
```

MAME 0.288 emulated a 0.257 ROM set. The capture validates callback-field placement and visible event/direction bits; it does not prove game acceptance of a physical spinner, analog mapping, player feel, or FPGA poll timing. The callback source is the basis for the precise one-step-per-read and half-turn tie behavior.
