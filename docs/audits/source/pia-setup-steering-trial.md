# Isolated PIA setup-steering trial

This is a proposed fitter experiment, not a production timing constraint. Its tracked candidate is [pia-setup-steering.sdc](../../../candidates/timing/pia-setup-steering.sdc); a scratch copy at `simulation/placement-bit5/setup-steering.sdc` is used by the isolated fit. Do not merge it into `Arcade-Exidy2.sdc` or the production QSF. The current design's ordinary related-clock timing remains the acceptance metric.

## Why this is a useful trial

The completed placement-bit5 full flow honored the source and destination location assignments for bit 5 (`FF_X37_Y16_N26` and `FF_X37_Y16_N25`). All eight audio-byte-stage to master-byte paths still missed setup; worst slack was −0.330 ns (bit 4), while bit 5 improved from −0.439 ns to −0.236 ns. Byte-path hold remained positive, worst +0.528 ns. A single-bit placement assignment improved one path but left seven misses, so a bounded setup objective on the whole byte is a more direct next experiment than changing random seed alone.

### What the archived reports say about delay source

The archived detailed setup/hold reports (`simulation/placement-bit5/completed-placement-only/timing-reports/pia-data-setup.rpt` and `pia-data-hold.rpt`) show both data-path delay and clock skew; the observed long interconnect delay cannot be attributed to hold repair from these reports alone. The setup path from bit 4 has 1.790 ns interconnect and 0.597 ns cell delay (2.387 ns total), against a 3.150 ns relationship and −0.763 ns clock skew, yielding −0.330 ns slack. Bit 5, whose source/destination FF sites were assigned adjacent, has 1.977 ns interconnect plus 0.337 ns cell delay (2.314 ns total), with −0.742 ns skew, yielding −0.236 ns slack. Its routed data path includes a `main_byte_data[5]~feeder` LABCELL and its interconnect; the delay is not explained by destination cell delay alone.

Across the eight setup paths, data interconnect is 1.771–2.012 ns and cell delay 0.335–0.609 ns; setup skew is −0.742 to −0.773 ns. Across the eight hold paths, interconnect is 1.452–1.617 ns and cell delay 0.117–0.359 ns; hold skew is +0.995 to +1.045 ns, and slack is +0.528 to +0.660 ns. Thus clock skew materially consumes setup margin, while path data delay is dominated by interconnect. The `asdata` name on bit 4's destination timing row is only the reported pin name and does not establish a reset-related cell penalty.

The fit report enables Optimize Hold Timing for all paths and estimates roughly 3,000 ns of hold-delay additions over the full design. However, the PIA source/destination endpoints do not appear in its top-100 `Estimated Delay Added for Hold Timing Details`, and the detailed PIA paths show no explicit buffer stage between source and destination. The local feeder LUT and the 1.45–1.62 ns hold-corner interconnect are compatible with a routed delay contribution, but the available evidence does not prove that the fitter intentionally inserted hold repair on these eight paths. The evidence supports a mixed physical path (substantial interconnect plus destination/feeder cell delay) and adverse setup skew, not a stronger causal claim.

The trial SDC adds `set_max_delay -from <8 source registers> -to <8 destination registers> 2.850`. This is 0.300 ns tighter than the baseline 3.150 ns related-clock setup relationship. If the fitter uses it to improve the selected routes, it remains only an optimization result: the candidate reports will have an artificial 2.850 ns target. A separate replay of the original, unmodified production SDC is required against the fitted candidate netlist to measure genuine setup and hold slack. That replay must show all eight data paths, hold checks, and no unintended collection matches before this placement is considered helpful.

Intel's Quartus 17.0 `set_max_delay` help defines the command as a maximum-delay exception that changes the setup relationship and says `-from`/`-to` accept register collections. Quartus documentation describes minimum and maximum delay constraints as overwriting the hold and setup relationships respectively. This trial uses only `set_max_delay`, leaving the original minimum/hold relationship unmodified; the original-SDC replay is still needed to confirm the actual hold results after routing. The installed Quartus 17.0.2 `quartus_sta --help` identifies the local TimeQuest executable. Intel's 17.0 command reference is [set_max_delay (::quartus::sdc)](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sdc_ver_1.5_cmd_set_max_delay.htm); the same-version command text states it is a maximum-delay exception, and the 18.1 Standard Edition guide describes minimum and maximum delays separately as hold and setup relationships.

## Candidate selector and flow

The candidate selects `*exidyPiaReturn:pia_return_data|audio_byte_stage*` to `*exidyPiaReturn:pia_return_data|main_byte_data*`, matching the registered endpoints in the current full-flow setup and hold reports. The SDC first requires each collection to contain exactly eight registers, then applies the max delay. These register-only wildcards avoid Tcl's bracket substitution and fail closed if hierarchy or optimization changes the endpoint population.

For an isolated project copy only:

1. Include `candidates/timing/pia-setup-steering.sdc` after the normal project constraints in the isolated fitter trial. Do not edit the production project or source SDC; keep its scratch copy separate during the active compile.
2. Run the full project compile as required by the project workflow.
3. Inspect the candidate SDC/reports to confirm the max-delay exception applies to exactly eight source-to-destination paths and doesn't alter other endpoints.
4. Replay the original production SDC and system SDC against that same fitted netlist. Record all eight setup and hold paths and compare to baseline `simulation/placement-bit5/timing-reports/pia-data-setup.rpt` and `pia-data-hold.rpt`.
5. Discard the trial if the original-SDC replay does not improve the worst path, worsens hold, moves violations to other master paths, or cannot establish an exact collection match.

This trial steers physical placement/routing only. It changes neither byte staging, reset, handshake, nor clock relationships, and it is not an exception to be retained in production. Passing replayed STA still does not validate the asynchronous hardware handshake or establish gameplay/audio acceptance.
