# Teeter Torture controls candidate

This is a standalone implementation candidate, not a connected Teeter build. It combines MiSTer spinner, D-pad, and analog input into a wrapping relative-dial target, then produces the Teeter `$5101` event byte and consumes the event only when T65 samples the registered CPU input byte. No production top, QIP, MRA, shared test runner, or other game profile was changed.

## Candidate behavior

[`rtl/teeter_controls.v`](../../../rtl/teeter_controls.v) follows the local Super Off-Road steering input pattern: spinner deltas add once when bit 8 toggles; D-pad and analog contributions update at `ce_frame`; and all motion accumulates modulo 256 so it remains queued until reads consume it. `DIAL_REVERSE` defaults to 1 to match MAME’s `PORT_REVERSE`. Spinner is 1:1. The 8-bit signed analog input is extended to 9 bits and maps through arithmetic shift by three, after an 8-count center deadzone (`ANALOG_DEADZONE=8`). The D-pad velocity mode ramps by 16 per frame to ±16 and decelerates by 16 after release; position mode ramps a spring-return deflection by 16 to ±127 and contributes deflection/8. `dpad_position_mode` is an input for a future OSD setting.

The pause input discards changed spinner deltas while still recording the new toggle state, and freezes frame ramp/position updates. It must be synchronous to `clk_sys` before connection. Motion received while paused is not replayed on release.

The adapter shifts MAME’s callback semantics into the actual bus bits: bit 6 means movement is pending; bit 2 is set for increment/positive direction and clear for decrement/negative direction. If the modulo-256 target distance is at least `0x80`, it decrements; exactly `0x80` also decrements, matching MAME’s strict `< 0x80` test. Each accepted CPU read advances the saved position by one count. Only bits 6 and 2 are replaced in `in0_other`; all other bits are preserved.

## CPU input-register timing contract

The adapter takes `cpu_read_strobe` and `cpu_read_data`. The strobe must exclude paused/RDY-stalled cycles and be a one-cycle pulse when T65 consumes the byte from the previous `CPU_databus_in` register, and `cpu_read_data` must be that exact registered byte. The cursor advances from the captured byte’s event/direction bits, not from a recomputed current combinational event. This matters because the dial accumulator can change on a master edge immediately before `PH_1`, while the CPU still samples the value registered from before that edge. The testbench models the continuously registered bus input followed by the later CPU sample and checks that the old byte controls consumption even when the current combinational direction has changed. This establishes a candidate interface contract; it does not prove that any unmodified Exidy2 read strobe is correctly aligned for integration.

When a future Teeter wrapper is written, construct `in0_other` from Teeter’s inputs, not the generic ESR joystick byte. MAME’s Teeter `IN0` defines bits 5 and 3 as unused active-low inputs, which should read high. Starts occupy bits 1:0, fire is bit 4, coin is bit 7, and the dial adapter owns 6/2. Reusing generic `m_up`/`m_left` on bits 5/3 would leak D-pad state into Teeter’s unused input bits. Keep the existing ESR mapping for all non-Teeter profiles.

## Verification

[`sim/teeter_controls/tb_teeter_controls.sv`](../../../sim/teeter_controls/tb_teeter_controls.sv) passes with Verilator 5.052. It checks spinner polarity/toggle qualification, queued motion, direction-bit encoding, per-read consumption, held-strobe protection, 8-bit wrap and exact-128 decrement, both D-pad ramp modes, analog deadzone/scaling/polarity, and paused-input consumption. A deliberately incorrect held-level consumer is included as a negative control and is shown to advance three counts while the candidate advances one. The paired `CPU_databus_in`/`PH_1` fixture checks registered-byte consumption at the one-master-edge boundary.

Reproduce from the repository root in the Archlinux WSL distribution:

```sh
verilator --binary --timing -Wno-fatal --top-module tb_teeter_controls \
  --Mdir simulation/test-logs/teeter-controls-obj \
  rtl/teeter_controls.v sim/teeter_controls/tb_teeter_controls.sv -o sim
simulation/test-logs/teeter-controls-obj/sim
```

The standalone controls checks and required-failure read-strobe control both passed. Generated build and execution logs remain ignored under `simulation/test-logs/`.

## Integration gates

The standalone tests do not determine preferred spinner sensitivity, D-pad feel, analog deadzone, or physical direction for an actual Teeter play session. The deadzone and scaling are candidate settings, not MAME source requirements. A production integration still needs a Teeter profile gate, `hps_io.spinner_0` wiring, a frame-enable source, synchronized pause/mode signals, correct Teeter base `IN0` bits, and a verified strobe/data binding to the T65 sample of `CPU_databus_in`. No MRA exists in this unit, and no game-level acceptance or Quartus build was run.

Source references: local style in `C:\MiSTerDev\SuperOffRoad_MiSTer\rtl\steering_input.sv`; pinned [MAME 0.288 Teeter input callback and port declaration](https://github.com/mamedev/mame/blob/mame0288/src/mame/exidy/exidy.cpp); and the verified mask-shifting behavior in [MAME 0.288 `dynamic_field::read`](https://github.com/mamedev/mame/blob/mame0288/src/emu/ioport.cpp).
