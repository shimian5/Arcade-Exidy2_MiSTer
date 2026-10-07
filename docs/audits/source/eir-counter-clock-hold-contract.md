# EIR capture and hold-path contract

## Finding

The cached timing report `simulation/timing-counter-diagnostic-2fafa6b/hold.rpt` records eight hold violations, with worst slack **−5.461 ns**. All endpoints are EIR data flops clocked by the internally generated interrupt event `rCPU_IRQ`; TimeQuest reports the latch relationship as `PH_6`. The failing sources are not one homogeneous static bus: they include the downloaded hardware profile, live joystick coin inputs, generated collision causes, and a graphics RAM output. Treating the full set as static or applying a broad false path would hide real capture behavior.

The report’s summary paths are:

| Slack | Source | EIR destination | Data-path context |
|---:|---|---|---|
| −5.461 ns | `mod_other[7]` | `EIR[3]` | profile-selected collision cause |
| −5.345 ns | `mod_other[6]` | `EIR[3]` | profile-selected collision cause |
| −5.221 ns | `mod_other[6]` | `EIR[4]` | profile-selected collision cause |
| −4.892 ns | `joystick_0[11]` | `EIR[5]` | coin B snapshot bit |
| −4.853 ns | `joystick_0[10]` | `EIR[6]` | coin A snapshot bit |
| −4.681 ns | `mod_other[6]` | `EIR[2]` | profile-selected collision cause |
| −4.659 ns | `mod_other[7]` | `EIR[2]` | profile-selected collision cause |
| −3.844 ns | `U11D_gfx` RAM port-A write register | `EIR[4]` | sprite/collision logic into cause bit 4 |

The numbers are from the cached report named above, not a new Quartus run. The report’s launch clock is the PLL output-counter `divclk`; its latch-clock label is `PH_6`. Its detailed path for EIR[3] shows a short source-to-data route (one logic level, 0.993 ns data delay) against 6.174 ns reported clock skew. The EIR[4] RAM path traverses sprite/collision combinational logic and has −3.844 ns hold slack.

## Source behavior behind those paths

In `Arcade-Exidy2.sv`, `clk_sys` is `clkm_45MHZ`; both `hps_io.clk_sys` and `exidy2.master_clock` receive that clock. `mod_other` is written on `clk_sys` only when `ioctl_wr && ioctl_index==1`, and the top-level reset includes `ioctl_download`. The profile byte therefore changes during download/reset and is ordinarily static during gameplay. It is not, however, a resettable EIR input: the EIR register has no `RESET_n` branch, and the source does not gate its capture while a new index-1 byte is being written. “Static during play” alone does not prove the byte cannot be captured while reset/download is active or at release.

`rtl/Exidy2.v` defines EIR as an event-time snapshot:

```verilog
always @(posedge rCPU_IRQ)
    EIR <= {!vscnt[8], !m_coina, !m_coinb,
            int_cause[4], int_cause[3], int_cause[2], 2'b00};
```

Bits 7, 6, and 5 snapshot video level, coin A, and coin B; bits 4:2 snapshot the profile-selected collision causes; bits 1:0 are zero. EIR is read at `$5103`. The IRQ event is separately maintained by an `always` block sensitive to `negedge BCLK`, `negedge COINT`, and `negedge nEIR`; its right-hand side includes `VL1`, `COINT`, and selected collision state. `COINT` itself is sampled from the coin inputs on `posedge master_clock`, but EIR’s coin bits use `m_coina`/`m_coinb` directly rather than that registered value. Therefore using COINT as evidence that the two EIR coin bits are already registered would be incorrect.

The collision path is also live. `exidyIntCause` selects mask/inversion from `pcb[7:6]`; its inputs are built from the sprite collision nets (`nM01VDT`, `nM02VDT`, `nSGCVID`, `CBLB`). EIR bit 4 includes the sprite-1/sprite-2 cause. The report’s path from the graphics RAM port-A write register through the `U14D_M1VA` shift-register logic and `INT_CAUSE` to EIR[4] confirms that the collision capture path is not merely profile configuration.

## Repair options and risks

1. **Move EIR capture into the master-clock domain with an explicit capture enable.** This is the strongest structural option for the joystick and collision hold paths because their source state is derived from the same master-clocked raster/input logic. It requires defining a synchronous IRQ/capture event and preserving the current event-time values for all eight EIR bits, the `$5103` read-clear behavior, and coin/vblank/collision coalescing. Simply replacing `posedge rCPU_IRQ` with `posedge master_clock` or `if (PH_6)` changes which old/new values are sampled: `PH_6` is itself assigned nonblocking in the master-clock counter process, and collision signals include registered timing/RAM state. Verify the exact old and new capture phase with a bus-level trace and tests across all profiles before adopting this.

2. **Synchronize and qualify the profile byte, then gate interrupt capture across profile download.** Since `mod_other` changes only during index-1 writes while the top-level reset includes `ioctl_download`, a master-clocked profile staging register (or two-stage synchronizer if the clock relationship is not guaranteed) can make the selected profile stable before run. Also prevent stale/partial-profile EIR capture during download and establish a defined EIR/IRQ state before reset release. This can isolate the profile-only exception candidate, but it does not repair joystick, collision, or RAM-to-EIR paths. Confirm that the selected index-1 value is complete and held through the qualification interval.

3. **Keep asynchronous event-clocked EIR and add delay/constraints.** This preserves the current sampling style most directly but leaves the clock-event architecture intact. A broad false path, a false path on all of `mod_other`, or a generic multicycle exception would suppress the observed hold failures without proving that the event captures a coherent byte. Do not use these as repairs. Any narrowly scoped exception for a profile bit would need a proven reset/download capture gate and a fresh report showing that only the intended static path is excepted; it cannot cover dynamic causes or joystick coin bits.

4. **Rely on fitter hold repair only after a full, correctly constrained flow.** This is a possible implementation outcome, not a source-level contract. The cached report shows violations after the reported fit, so any new full-flow result must show that the exact EIR endpoints close and that the intended launch/latch clocks and exception matches are correct. No conclusion about a later build is made here.

## Verification needed before closure

Use the full-flow STA report after any RTL change. Inspect all EIR hold paths, the launch/latch clock identities, and exception match counts. Functionally compare the original and candidate EIR values at the exact `$5103` interrupt snapshot for simultaneous collision, coin, and vblank events; read-clear timing; all four profile values; and download/reset assertion/release with index-1 writes. Include a test where collision/RAM state changes at adjacent PH_6/master-clock edges so a one-cycle old/new sampling shift is visible. This source audit makes no RTL/SDC change and does not claim the hold issue is repaired.
