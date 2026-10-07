# Post-build clock/event coverage diagnostic

`tools/timing/report_remaining_coverage.tcl` is a read-only TimeQuest report script for use after a completed full Quartus flow. It loads the production root and system SDCs into the fitted timing netlist, inventories resolved clocks, enumerates sequential registers and their clock-pin associations when the local Quartus API exposes them, and writes focused PIA return-data/valid timing reports.

Run it from the project root after the build has finished:

```text
quartus_sta -t tools/timing/report_remaining_coverage.tcl
```

An optional first argument selects the report directory. By default outputs go under `simulation/timing-remaining-coverage/`, which is ignored build output. The script does not edit SDC, add constraints, fit, or assemble the project.

## What the reports establish

- `clocks.rpt` and the resolved-clock list report clock objects and periods that TimeQuest recognizes after both SDC files are loaded.
- `sequential-endpoints.txt` lists fitted registers matched by source-reviewed event-state selectors. `clock-group-members.txt` resolves each wildcard pattern from the root SDC's exclusive clock-group assignment against post-fit clock objects, showing each group's actual members.
- `pia-data-setup.rpt` and `pia-data-hold.rpt` report the ordinary timed byte path from `audio_byte_stage[7:0]` to `main_byte_data[7:0]`.
- `pia-valid-recovery.rpt` and `pia-valid-removal.rpt` examine asynchronous reset timing at `main_byte_valid`. `pia-valid-read-setup.rpt` and `pia-valid-read-hold.rpt` show the master-domain validity mask through the PIA/CPU read path to `CPU_databus_in[7:0]`.
- `check-timing.rpt`, `exceptions.rpt`, and `applied-sdc.rpt` are optional runtime reports. If a command is absent or its options are rejected, the summary records that result. Use a successful `check_timing` report to investigate unconstrained endpoints; the direct-target comparison above is not a substitute. Review exception and SDC reports to determine which exceptions and clock groups actually resolve. An absent or failed report is not evidence of complete timing or safe exceptions.

The event inventory selectors correspond to the source categories in [remaining-clock-coverage.md](remaining-clock-coverage.md): CPU write strobes, raster/load events, sprite shift registers, IRQ/EIR event state, audio timer event state, and the PIA return pipeline. They are only endpoint selectors; the diagnostic does not turn event pins into clocks or propose exceptions.

## Evidence status and limits

The first run against full build `07a49c5` confirmed `report_exceptions` is supported and reports false-path reach. It rejected `check_timing -verbose`; the script now uses the `-file` option shown by Quartus 17's runtime usage text. `get_register_info -clock` returned empty results when probed and did not classify register coverage, so that probe was removed. The `check_timing` report gives actual no-clock checks, while the script resolves SDC wildcard group memberships separately. Those results answer different questions: group membership alone does not establish every path's exception reach.

Even a successful run only describes static fitted-netlist timing analysis. It does not prove event-clock functional equivalence, asynchronous event capture correctness, reset behavior on hardware, metastability robustness, or game acceptance. Review any exception report alongside the loaded SDC and path endpoints; do not treat a positive summary or a missing report as proof that all paths are covered.
