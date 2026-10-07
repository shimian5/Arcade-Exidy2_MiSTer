# A4 noise recurrence and tap step comparison

This bounded GHDL check compares the production-selected `modules/6840/berzerk_sound_fx.vhd` against an independent four-word implementation of the pinned MAME recurrence. It tests the mathematical state update and then checks MAME's literal event predicate against the production RTL's actual registered pulse. It does not establish the original PCB tap or prove audible game behavior.

## Inputs and guards

- Production VHDL SHA256: `CC8A67374B764B4DB58B6FF4509BBA742F2469070F26FFC0E655AC501156BAB7`.
- Pinned `simulation/reference_sources/exidysound.cpp` SHA256: `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660`; MAME reference is the repository's pinned 0.288 snapshot, commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`.
- The generated copy at ignored `simulation/harness/a4_noise_ghdl/berzerk_sound_fx.vhd` adds debug output ports and simulation-only initial values for `noise_xor_r`, tap history, and external pulse. The production source does not reset all of these; the guards establish MAME's explicit zero delayed-XOR reset and a defined first edge for this recurrence experiment. `prepare_noise_model.py` asserts unique source anchors and writes the source byte hash beside the generated copy.
- `sim/audio_6840/tb_noise_contract.vhd` models MAME's four `uint32_t` words independently, applies the literal high-bit feedback and word carries, and compares the concatenated state after every selected production shift. It then compares every MAME post-shift `(word2 & 3) == 1` event with each rising edge of production vector bit 95, while separately checking the real `ena_external_clock` output against its source-level registered edge-detector behavior.

Run with `make -C sim/harness noise-contract` in the configured WSL GHDL environment. The successful log at `simulation/harness/a4_noise_ghdl/run.log` reports:

```
RESULT steps=512 mame_postshift_low2_events=12 rtl_registered_bit95_pulses=12 event_position_mismatches=22 prescale_div8_aggregate_mame=1 prescale_div8_aggregate_rtl=1
PASS noise recurrence; MAME and RTL tap events counted and compared by step
```

The 512 consecutive state assertions pass exactly: after each shift, the production vector equals `{MAME word3, word2, word1, word0}`. Both event predicates count 12 in this window, but 22 of the 512 per-step event bits differ. Thus the same aggregate count is not evidence that the tap pulse train is aligned. With an abstract divide-by-eight accumulator, each 12-event stream yields one completed group; this test does not program timer 3 or assert its output toggles, and phase differences can change which later event completes a group.

## What this establishes

The feedback polynomial, word ordering, shifts, carries, and delayed XOR agree for the tested 512 transitions when reset is explicitly initialized as MAME does. It confirms that the VHDL's *registered bit-95 edge detector* behaves as written, including its registered pulse timing. It disproves a claim that the two literal tap event sequences are identical in this run, despite equal counts.

The 22 event-position mismatches do not by themselves identify which tap is electrically correct. MAME's expression checks the post-shift low two bits of `LFSR_2`; its adjacent comment calls that the “96th bit.” The RTL detects a rising edge of vector bit 95. The observed software-model divergence is evidence for a focused hardware/reference investigation, not authorization to change RTL. The source comparison also says nothing about actual PCB wiring, chip internal convention, analog filtering, or a captured noise waveform.

The fixture has no game ROM dependency and no Quartus/STA interaction. It does not exercise MAME's `noisy`/channel-inhibit gate or control writes; its clock is continuous after startup. A next test should separately drive MAME-style timer controls and compare external timer event ordering, including actual VHDL timer-3 divide-by-eight state/output, without weakening the per-step recurrence or tap assertions.
