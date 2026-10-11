# Mouse Trap voice I/O/control helper — 2026-10-11

## Source contract

The candidate is based on the local pinned MAME reference at `simulation/reference_sources/exidysound.cpp`: `voiceio_w` (lines 639–646), `voiceio_r` (649–664), `cvsd_data_w` (667–671), constructor defaults (610–611), RIOT callback binding (700), and I/O map (685–688). The adjacent design audit records the target MAME source revision as `27a8d9e85b58058965907d1d8a7a92f8ed039348` and notes that preserved local source copies may have distinct provenance. The local source SHA-256 is `57c0edc71e9faf0a37e48eef406586e95a95902ef0f9e53275a7ad3326fad660`.

`voiceio_r` starts with `0xff`; when address bit 7 is clear, it replaces the low nibble with `{cvsd_data[3], cvsd_data[0], cvsd_data[2], cvsd_data[1]}`; when address bit 6 is clear, it replaces bit 7 with the CVSD clock state. These address tests are independent and apply to all 256 I/O aliases. `voiceio_w` independently writes D0 to the CVSD digit input when address bit 4 is clear and to RIOT PB0 when bit 5 is clear. `cvsd_data_w` saves its byte and controls the speech CPU reset from bit 4; MAME's constructor initializes the saved byte and CVSD clock low.

The candidate in [mousetrap_voice_io.v](../../../rtl/mousetrap_voice_io.v) makes active-high T80 `io_wr` a one-transaction edge input: a high interval is accepted once, and a low interval rearms it for the next transaction. It latches `cvsd_digit` and `riot_pb0_in` on that accepted event, including both effects when both address selects are active. A separate RIOT PA callback-commit input captures the callback byte once. No ROM data, decoder, audio filter, QIP entry, or production instance is part of this unit.

## RIOT and reset boundary

The local [R6532.vhd](../../../modules/riot/R6532.vhd) exposes `pa_out` and `pb_out` as resolved pin values, not raw ORA/ORB latches: on falling `phi2`, each output is `(output_latch & DDR) | (input_pins & ~DDR)` (lines 348–349). The helper therefore receives both the RIOT PA callback byte and resolved `riot_pa_pins`; it captures the byte for MAME-style status reads and uses resolved PA4 as the active-high reset-release pin, combined with the external global Z80 reset. PB0 writeback is exposed as an RIOT input pin, so the actual R6532 DDR equation determines whether it appears on the physical PB0 pin or the ORB output latch.

This separation matches the local R6532 electrical pin semantics and MAME's saved callback byte as two distinct signals. The local `reference_sources` snapshot does not include the MOS6532 callback implementation, so the exact MAME callback interaction with PA DDR is still an integration detail to verify. The helper keeps decoder reset on a separate `decoder_reset_n` input/output path; toggling the CPU reset cannot reset or overwrite CVSD state.

## Verification

Run from PowerShell with installed ModelSim 10.5b:

```powershell
& .\sim\mousetrap_voice_io\run_fixture.ps1
```

The fixture compiles the actual local R6532 VHDL and the candidate helper. It checks all 256 I/O addresses for each of 256 CVSD status bytes and both clock states (131,072 read cases), then all 256 addresses against all 256 write-command bytes (65,536 write cases). During every held `io_wr` case, it changes D0 after the first accepted edge and verifies the output latches do not repeat the side effect. It also holds the RIOT callback commit high while changing its data and verifies a single capture.

The actual R6532 instance checks PA4 reset release/assertion with DDRA output, input PA4 following `pa_in`, callback-byte capture, and PB0 direction behavior with DDRB input/output. The fixture separately toggles global CPU reset and decoder reset and checks they remain independent. The passing run `simulation/harness/mousetrap_voice_io/modelsim-20261011-160907-773/` printed:

```text
PASS Mouse Trap voice I/O: exhaustive reads=131072 writes=65536 R6532 DDR pins and independent reset
```

ModelSim reported zero errors and warnings. The test does not instantiate T80, the CVSD decoder, the production audio board, the ROM transport, or the full speech system. It establishes the helper truth table and local RIOT pin interaction only.

## Integration gates

The next integration step must derive the RIOT PA commit and callback-data inputs from the accepted PA write, preserve R6532 pin timing, connect `riot_pb0_in` to `pb_in[0]`, pass the separately managed decoder reset, and gate Z80 reset with both profile/image readiness and PA4. Before production binding, join the actual T80 `io_rd/io_wr` signals to this helper with a synthetic program to confirm the active-high write pulse/deassertion sequence and accepted-edge alignment. Validate the MOS6532 PA callback's DDR semantics against the exact emulator/device implementation if that source is admitted for the integration audit.

Root independently replayed the same actual-R6532 fixture: PASS, zero errors/warnings, `simulation/harness/mousetrap_voice_io/modelsim-20261011-161303-614/`. The callback-DDR and actual-T80 integration gates above remain open.
