# A4 timer-3 external event and divide-by-eight ordering

This isolated GHDL fixture compares the selected production 6840 VHDL's real LFSR-generated external pulses and timer-3 output against a small source-derived MAME event model. It establishes the current cycle ordering in this configuration; it is not a hardware waveform or whole-game audio acceptance test.

## Source behavior

Pinned MAME 0.288 (`simulation/reference_sources/exidysound.cpp`, commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`) updates noise inside `sound_stream_update`. It first computes the sample's E-clock count. Noise advances only when at least one timer selects external clock (`noisy`, line 285) and channel 0 is enabled; with SFX control bit 0 clear, the LFSR advances before timer 0. The resulting post-shift `LFSR_2 & 3 == 1` matches are counted by `sh6840_update_noise` (lines 106–132). The third timer then selects E clocks or that noise-event count from its control bit 1; when prescale bit 0 is set, it adds the saved remainder, stores modulo 8, divides the event count by 8, and calls `sh6840_apply_clock` in the same sample (lines 324–340). The output state toggles in that helper only when the resulting timer clock count crosses the current counter value (lines 51–98). MAME's timer-register write handler calls `m_stream->update()` before changing a control or period; the LSB write loads the counter immediately when CR4 is clear (lines 425–474).

In the selected VHDL, the LFSR shifts from the selected E or channel-0 rising event without MAME's `noisy`/channel-0-inhibit gate. Its external tap is a registered rising-edge detector on vector bit 95 (`noise_shift_reg_95_r` / `ena_external_clock`, lines 98–105). `raw3` selects internal E or that delayed external enable; `pre3` advances when raw3 is high and CR3 bit 0 is set; `tick3` is combinational from raw3 and the current pre3 value (lines 283–297). The timer process samples the previous signal values on a parent-clock edge, gives registered `load3` priority, and otherwise uses `tick3` to decrement or toggle q3 (lines 224–236). Thus a noise transition, its sampled bit-95 edge, raw3, prescaler advancement, tick3, and output-state change are distinct phases. Equal event totals do not imply equal output phase.

## Fixture and result

The fixture programs CR0=`02` (enabled, internal E), CR1=`00` (external, keeping MAME's noise optimization active), CR3=`81` (external, divide by eight, output enabled), and timer-3 period `0001`. It advances one synthetic 6840 E clock per fixture sample with SFX control left at its reset value. A source-derived four-word MAME model asserts the full LFSR state against the guarded copy on every sample. A separate RTL-order checker asserts pre3, timer-3 counter, and q3 against the prior-cycle raw3/tick3 sequence, including LSB-load latency. It then compares actual q3 transition times with MAME's output state.

GHDL 6.0.0 produced:

```text
RESULT cycles=5009 mame_noise_events=786 rtl_external_pulses=785 mame_timer3_toggles=49 rtl_timer3_toggles=49 first_mame_toggle_cycle=641 first_rtl_toggle_cycle=674 output_phase_divergences=1615 first_divergence_cycle=641 first_mame_q='1' first_rtl_q='0'
PASS timer3 output tracked against MAME and RTL event ordering
```

The first output transition is 33 synthetic parent cycles apart; q3 differs for 1,615 sampled cycles even though both sides produce 49 transitions in this finite window. The noise states agree sample-by-sample. The one-event count difference at the capture boundary is consistent with the registered edge-detection pipeline and must not be interpreted as a steady-state event-rate error. The observed phase separation is a source/model result for this startup, clock ratio, control sequence, and tap—not a measured board or game latency.

## Reproduction

From the repository root, generate the guarded source copy. The helper accepts only the selected production VHDL SHA256 `CC8A67374B764B4DB58B6FF4509BBA742F2469070F26FFC0E655AC501156BAB7`; it adds debug ports and simulation initial values for the otherwise uninitialized LFSR delay and edge-history registers. The production source is not edited.

```powershell
python tools/audio_6840/prepare_timer3_event_model.py --output simulation/audio_6840_timer3/berzerk_sound_fx.vhd
```

Then run in the existing Arch WSL environment with the bundled GHDL 6.0.0 package (no install):

```powershell
wsl.exe -d archlinux -- bash -lc 'set -e; cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/audio_6840_timer3; export LD_LIBRARY_PATH=/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -a --std=08 -fsynopsys -frelaxed berzerk_sound_fx.vhd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/sim/audio_6840/tb_timer3_event_order.vhd; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -e --std=08 -fsynopsys -frelaxed tb_timer3_event_order; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -r --std=08 -fsynopsys -frelaxed tb_timer3_event_order --assert-level=error --stop-time=55us --ieee-asserts=disable > run.log 2>&1; grep -q "PASS timer3 output tracked against MAME and RTL event ordering" run.log; tail -30 run.log'
```

The reference source SHA256 is `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660`. The testbench SHA256 is `188C7DB44BEF599C0E92092CAD746781B8A1F659453D2B2432CBD6ADB4418458`; generator SHA256 is `47252AB526545852BC0F1ACA3AC5DF90BE4A4C77766A23F3A025FDEBC51FC03F`. Generated VHDL, GHDL work files, and `run.log` stay under ignored `simulation/audio_6840_timer3/`. The root independently replayed the test from a fresh ignored run directory and confirmed the result.

## Limits and next use

This fixture configures a one-E-clock-per-sample model to make MAME's stream update order explicit; it does not model MAME's fractional 6840-clock/sample accumulator at the production sound rate. It verifies event ordering and output phase for one timer-3 setting, not reset corner cases, all control transitions, or physical PCB wiring. The adjacent 512-step recurrence fixture separately demonstrates that MAME's literal tap and VHDL bit-95 event positions differ. Before using an in-game capture to alter production logic, validate the intended hardware tap mapping and compare a timer-3 output trace with a pinned, accurately timed MAME stream sequence. No production VHDL, Quartus project, MAME ROM, or existing pending work files were changed.
