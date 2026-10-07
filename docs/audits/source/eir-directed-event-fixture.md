# Directed Exidy IRQ/EIR event fixture

## Result

The source-extracted event fixture passes on Verilator 5.052. It exercises the current `rtl/Exidy2.v` event block without copying its behavior into a handwritten model. The extracted production span includes the `exidyIntCause` instantiation, legacy/profile collision selection, `COINT` sampling, `rCPU_IRQ` set/clear process, and EIR snapshot process. It compiles the actual `rtl/int_cause.v` helper.

The directed cases establish these current-source behaviors for a static profile-1 setup:

- A vblank-level event at the BCLK sampling edge raises `rCPU_IRQ` and captures the source's profile-1 EIR value (`0x84`) when both coin inputs are inactive and `vscnt[8]` is zero.
- A falling active-low coin input is sampled into `COINT` on `posedge master_clock`. After that sample, restoring the raw coin input before the BCLK event leaves the IRQ request asserted by `COINT`, while EIR captures the restored live coin level. This demonstrates that the event term and snapshot field use different temporal values in the existing RTL.
- The profile-1 collision mask can assert the interrupt event while the profile-selected, inverted EIR cause bit is zero. EIR captures that actual helper output (`0x80` for the directed input combination).
- Reading `$5103` asserts active-low `nEIR`, which clears `rCPU_IRQ`; it does not clear EIR. EIR retains the last event snapshot until a later rising edge of `rCPU_IRQ`.
- A vblank event coincident with `nEIR` assertion is suppressed by the `& nEIR` gate in the event equation. A source held during the read likewise does not produce a new IRQ edge or EIR capture.

The checked source order is: master-clock sampling updates `COINT`; a BCLK falling edge evaluates the level-sensitive event equation; a rising `rCPU_IRQ` captures EIR; and an `nEIR` falling edge clears `rCPU_IRQ`. The input pattern keeps profile 1 (`pcb[7:6]=01`) static while exercising both vblank and a profile-selected collision.

These are RTL-derived observations, not a hardware acceptance claim or a proposed timing repair. The fixture does not instantiate the CPU or bus decoder; its testbench drives `nEIR` directly to represent the `$5103` read-select event. It also does not model analog pin timing, metastability, fitted delay, reset, or physical simultaneity. Production `COINT`, `rCPU_IRQ`, and `EIR` have no reset in the extracted span; the test first samples inactive coins and generates a real source event to establish known values. Do not infer a defined cold-start state from this test.

## Reproduction

From a Windows PowerShell prompt in the repository root, run:

```powershell
python tools/eir_event/run_fixture.py
```

The runner extracts the guarded span from current `rtl/Exidy2.v`, writes generated HDL and full compile/simulation logs under ignored `simulation/eir_event/`, compiles the actual `rtl/int_cause.v`, and writes `result.json` there. Each invocation gets a fresh timestamped execution directory, and a successful run requires zero compile/simulation exit codes, all 14 assertion `PASS` lines, and the final fixture pass marker. The build sets `MAKEFLAGS=OPT_FAST=-O0` for the installed Arch Verilator 5.052 environment. Override the ignored run directory or JSON location with `--run-dir` and `--report`; both must remain under `simulation/`. The extraction-only check is `python tools/eir_event/run_fixture.py --extract-only`.

## Provenance and scope

The extraction runner checks a unique `reg cDET,rCPU_IRQ,COINT;` start anchor, one active EIR-capture end line, and presence of the production helper and IRQ event process. It records hashes for the full source file, testbench template, extracted span, and generated HDL in the JSON result. The Verilator log contains a `COMBDLY` warning for the source's nonblocking assignment in the combinational legacy `cDET` block; Verilator documents that it executes that assignment as blocking. This fixture uses profile 1, where `cDET_sel` comes from `int_coll_irq & nCBLB`, so the legacy `cDET` path is not used by its collision assertion. Profile 0's event path is outside this directed fixture. No production RTL, SDC, MRA, release, ROM, or Quartus file is changed.

Source references are [the event and EIR logic in `rtl/Exidy2.v`](../../../rtl/Exidy2.v#L655) and [the production `exidyIntCause` helper](../../../rtl/int_cause.v). The existing [EIR capture and hold-path audit](eir-counter-clock-hold-contract.md) provides the source-level clock and path context. The standalone [profile truth-table fixture](../../../sim/int_cause/tb_int_cause.sv) is separate; this directed fixture specifically validates the extracted event/read-clear integration around that helper.
