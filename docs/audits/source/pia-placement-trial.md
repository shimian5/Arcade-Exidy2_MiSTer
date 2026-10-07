# PIA byte-register placement trial

The fitted `07a49c5` design has eight ordinary timed setup violations from `audio_byte_stage[*]` to `main_byte_data[*]`. The worst is bit 5 at -0.439 ns. Its source is placed at `FF_X37_Y16_N26`; its destination is at `FF_X37_Y20_N8`. The data path has 1.880 ns interconnect and 0.612 ns destination-cell delay. The destination is a plain master-clock data FF in RTL; its fitted pin label `asdata` does not mean the register has an asynchronous reset.

The read-only location query `get_node_info -location $register` succeeded on this fit. `simulation/timing-register-sites-07a49c5/fitted-register-sites.tsv` records every fitted register's name and location. At `FF_X37_Y16`, occupied FF sites include N10, N19, N26, N32, N34, N35, N43, N50, N53, and N55; the inventory contains no register at N25. The suffix N25 is used by fitted FF sites elsewhere in the design, so it is an observed-valid suffix, but this does not certify that `FF_X37_Y16_N25` is a legal free device site. Quartus must validate the assignment.

`candidates/timing/pia-placement.qsf` is a one-bit assignment fragment for a throwaway project/revision. It explicitly anchors the source to its current `FF_X37_Y16_N26` site and proposes `main_byte_data[5]` at `FF_X37_Y16_N25`. The QSF targets use braces so Tcl treats `[5]` as literal bus notation. Do not add this fragment to the production QSF. The target strings and site legality remain subject to fitter validation. The experiment changes no RTL, SDC, clock, or protocol behavior.

For a controlled trial, copy the project to a temporary checkout, add this fragment only to the copied QSF, then run the full Quartus project flow. Confirm in the new fitter report that the destination assignment was honored and inspect the resulting Q-path and clock-tree path. Compare all eight setup and hold paths, not only bit 5. The baseline minimum hold slack is +0.252 ns, so reducing route delay may worsen hold. Keep the candidate only if fitter accepts it and setup improves without creating a hold violation or displacing other critical paths. A one-bit placement trial cannot close the remaining seven paths by itself.

## Full-byte baseline path table

| Bit | Setup slack (ns) | Clock skew (ns) | Data delay (ns) | Q-to-destination interconnect (ns) | Destination site |
|---:|---:|---:|---:|---:|---|
| 5 | -0.439 | -0.767 | 2.492 | 1.880 | `FF_X37_Y20_N8` |
| 7 | -0.430 | -0.720 | 2.530 | 2.193 | `FF_X37_Y18_N37` |
| 6 | -0.390 | -0.770 | 2.440 | 2.101 | `FF_X37_Y20_N50` |
| 1 | -0.357 | -0.771 | 2.406 | 2.071 | `FF_X37_Y20_N52` |
| 3 | -0.317 | -0.739 | 2.398 | 2.061 | `FF_X33_Y16_N31` |
| 4 | -0.305 | -0.737 | 2.388 | 2.051 | `FF_X33_Y16_N13` |
| 0 | -0.243 | -0.734 | 2.329 | 1.994 | `FF_X36_Y18_N34` |
| 2 | -0.153 | -0.766 | 2.207 | 1.870 | `FF_X37_Y20_N11` |

Bits 7, 6, 1, 3, 4, 0, and 2 include a fitted `~feeder` cell (about 0.075–0.077 ns) and destination FF cell delay (about 0.260–0.262 ns). Bit 5 has the separate 0.612 ns destination-cell delay. All byte paths remain timed between the core PLL outputs in the same resolved exclusive group; the group does not cut these paths.

## Completed isolated full flow

The source-checkpoint `68bd584` copy completed the full Quartus 17.0.2 flow on 2026-10-07, 14:59:37–15:12:29 local: exit 0, zero errors, 284 warnings. Post-fit register inventory confirms source bit 5 at `FF_X37_Y16_N26` and destination bit 5 at `FF_X37_Y16_N25`; both assignments were honored. The initial scratch-QSF newline error was corrected before this flow.

| Bit | Setup slack (ns) | Clock skew (ns) | Data delay (ns) |
|---:|---:|---:|---:|
| 4 | -0.330 | -0.763 | 2.387 |
| 6 | -0.323 | -0.763 | 2.380 |
| 7 | -0.293 | -0.766 | 2.347 |
| 0 | -0.258 | -0.766 | 2.312 |
| 1 | -0.240 | -0.773 | 2.287 |
| 5 | -0.236 | -0.742 | 2.314 |
| 3 | -0.161 | -0.766 | 2.215 |
| 2 | -0.116 | -0.757 | 2.179 |

Worst master setup is -0.330 ns, TNS -1.957 ns; audio setup is +24.038 ns. Byte hold remains positive, minimum +0.528 ns. The five constrained divider domains pass their reported setup/hold. Bit 5 improved by 0.203 ns, but all eight byte paths still fail setup. The result does not justify promoting the placement fragment to production or accepting its RBF.

Completed outputs are preserved under ignored `simulation/placement-bit5/completed-placement-only/` (full-flow log, output files, register inventory and timing replay). Trial RBF SHA256: `13092af62823daf244d9c30189c507284023255d0f959558f2887c1bce518e14`. Production RTL/QSF/SDC and releases remain unchanged. A separate [setup-steering experiment](pia-setup-steering-trial.md) follows; acceptance uses the original production constraints.
